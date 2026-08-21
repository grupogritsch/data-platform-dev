import psycopg2
from dotenv import load_dotenv
import os

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

conn = psycopg2.connect(
    host='192.168.0.37',
    port=5433,
    database=os.getenv('DW_NAME'),
    user=os.getenv('DW_USER'),
    password=os.getenv('DW_PASSWORD')
)
cur = conn.cursor()

print("1. Ajustando a tabela torre.map_veiculo_rastreador para suportar MÚLTIPLOS RASTREADORES por placa...")

cur.execute("""
    ALTER TABLE torre.map_veiculo_rastreador DROP CONSTRAINT IF EXISTS map_veiculo_rastreador_pkey CASCADE;
    ALTER TABLE torre.map_veiculo_rastreador DROP CONSTRAINT IF EXISTS map_veiculo_rastreador_placa_key CASCADE;
    ALTER TABLE torre.map_veiculo_rastreador ADD PRIMARY KEY (placa, provedor_rastreador);
""")

print("2. Inserindo / Atualizando todos os provedores identificados no DW...")

# 2.1 Inserir 3STEC
cur.execute("""
    INSERT INTO torre.map_veiculo_rastreador (placa, provedor_rastreador, origem_mapeamento, observacao, atualizado_em)
    SELECT DISTINCT 
        UPPER(REPLACE(t.placa, '-', '')) AS placa,
        '3STEC' AS provedor_rastreador,
        'API' AS origem_mapeamento,
        'Validado via API 3sTec (ListaVeiculos)' AS observacao,
        NOW()
    FROM bronze.tres_s_veiculos t
    JOIN torre.gold_dim_veiculo v ON UPPER(REPLACE(v.placa, '-', '')) = UPPER(REPLACE(t.placa, '-', ''))
    WHERE v.situacao_veiculo NOT IN ('VENDIDO', 'BAIXADO')
    ON CONFLICT (placa, provedor_rastreador) DO UPDATE SET
        origem_mapeamento = EXCLUDED.origem_mapeamento,
        observacao = EXCLUDED.observacao,
        atualizado_em = NOW();
""")
r_3s = cur.rowcount
print(f"• 3STEC: {r_3s} registros processados.")

# 2.2 Inserir OMNILINK (via Nuxeo)
cur.execute("""
    INSERT INTO torre.map_veiculo_rastreador (placa, provedor_rastreador, origem_mapeamento, observacao, atualizado_em)
    SELECT DISTINCT 
        UPPER(REPLACE(n.placa, '-', '')) AS placa,
        'OMNILINK' AS provedor_rastreador,
        'API (NUXEO)' AS origem_mapeamento,
        'Equipamento Omnilink integrado e validado via Gateway Nuxeo' AS observacao,
        NOW()
    FROM bronze.nuxeo_veiculos_posicao n
    JOIN torre.gold_dim_veiculo v ON UPPER(REPLACE(v.placa, '-', '')) = UPPER(REPLACE(n.placa, '-', ''))
    WHERE (n.complemento ILIKE '%omnilink%' OR n.serial ILIKE '%omnilink%')
      AND v.situacao_veiculo NOT IN ('VENDIDO', 'BAIXADO')
    ON CONFLICT (placa, provedor_rastreador) DO UPDATE SET
        origem_mapeamento = EXCLUDED.origem_mapeamento,
        observacao = EXCLUDED.observacao,
        atualizado_em = NOW();
""")
r_omni = cur.rowcount
print(f"• OMNILINK: {r_omni} registros processados.")

# 2.3 Inserir NUXEO (próprio)
cur.execute("""
    INSERT INTO torre.map_veiculo_rastreador (placa, provedor_rastreador, origem_mapeamento, observacao, atualizado_em)
    SELECT DISTINCT 
        UPPER(REPLACE(n.placa, '-', '')) AS placa,
        'NUXEO' AS provedor_rastreador,
        'API' AS origem_mapeamento,
        'Validado via API Nuxeo' AS observacao,
        NOW()
    FROM bronze.nuxeo_veiculos_posicao n
    JOIN torre.gold_dim_veiculo v ON UPPER(REPLACE(v.placa, '-', '')) = UPPER(REPLACE(n.placa, '-', ''))
    WHERE NOT (n.complemento ILIKE '%omnilink%' OR n.serial ILIKE '%omnilink%')
      AND v.situacao_veiculo NOT IN ('VENDIDO', 'BAIXADO')
    ON CONFLICT (placa, provedor_rastreador) DO UPDATE SET
        origem_mapeamento = EXCLUDED.origem_mapeamento,
        observacao = EXCLUDED.observacao,
        atualizado_em = NOW();
""")
r_nux = cur.rowcount
print(f"• NUXEO: {r_nux} registros processados.")

# 3. Recriar a View Consolidada com suporte a Multi-Rastreadores
print("3. Atualizando a View Consolidada torre.vw_veiculo_rastreador_consolidado...")
cur.execute("""
    CREATE OR REPLACE VIEW torre.vw_veiculo_rastreador_consolidado AS
    WITH agg_rastreadores AS (
        SELECT 
            placa,
            COUNT(*) AS qtd_rastreadores,
            STRING_AGG(provedor_rastreador, ' + ' ORDER BY provedor_rastreador) AS rastreadores_instalados,
            STRING_AGG(origem_mapeamento, ', ' ORDER BY provedor_rastreador) AS origens_mapeamento,
            MAX(atualizado_em) AS ultimo_mapeamento
        FROM torre.map_veiculo_rastreador
        GROUP BY placa
    )
    SELECT 
        v.placa,
        v.modelo_raw AS modelo,
        v.montadora,
        v.ano_fabricacao,
        v.ano_modelo,
        v.grupo_veiculo,
        v.filial_operacional,
        v.situacao_veiculo,
        COALESCE(a.qtd_rastreadores, 0) AS qtd_rastreadores,
        COALESCE(a.rastreadores_instalados, 'PENDENTE DE MAPEAMENTO') AS rastreadores_instalados,
        CASE 
            WHEN COALESCE(a.qtd_rastreadores, 0) > 1 THEN TRUE 
            ELSE FALSE 
        END AS possui_multi_rastreador,
        COALESCE(a.origens_mapeamento, 'NÃO IDENTIFICADO') AS origens_mapeamento,
        a.ultimo_mapeamento
    FROM torre.gold_dim_veiculo v
    LEFT JOIN agg_rastreadores a ON UPPER(REPLACE(a.placa, '-', '')) = UPPER(REPLACE(v.placa, '-', ''));
""")

conn.commit()
print("✅ View torre.vw_veiculo_rastreador_consolidado recriada com SUCESSO!")
conn.close()
