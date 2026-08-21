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

# 1. Dropar todas as constraints de unicidade antigas
cur.execute("""
    ALTER TABLE torre.map_veiculo_rastreador DROP CONSTRAINT IF EXISTS map_veiculo_rastreador_pkey CASCADE;
    ALTER TABLE torre.map_veiculo_rastreador DROP CONSTRAINT IF EXISTS map_veiculo_rastreador_placa_key CASCADE;
    ALTER TABLE torre.map_veiculo_rastreador DROP CONSTRAINT IF EXISTS uq_map_veiculo_rastreador_placa_prov CASCADE;
    
    -- Criar a chave primária composta (placa + provedor_rastreador)
    ALTER TABLE torre.map_veiculo_rastreador ADD PRIMARY KEY (placa, provedor_rastreador);
""")

print("✅ Chave primária de torre.map_veiculo_rastreador alterada para (placa, provedor_rastreador)!")

# 2. Inserir 3STEC
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
print(f"• 3STEC: {cur.rowcount} registros.")

# 3. Inserir OMNILINK
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
print(f"• OMNILINK: {cur.rowcount} registros.")

# 4. Inserir NUXEO
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
print(f"• NUXEO: {cur.rowcount} registros.")

conn.commit()

# 5. Consultar resumo de veículos com múltiplos rastreadores
cur.execute("""
    SELECT 
        rastreadores_instalados,
        COUNT(*) AS total_veiculos,
        ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM torre.vw_veiculo_rastreador_consolidado WHERE situacao_veiculo NOT IN ('VENDIDO', 'BAIXADO')), 1) AS percentual
    FROM torre.vw_veiculo_rastreador_consolidado
    WHERE situacao_veiculo NOT IN ('VENDIDO', 'BAIXADO')
    GROUP BY rastreadores_instalados
    ORDER BY total_veiculos DESC;
""")

print("\n=== DISTRIBUIÇÃO ATUALIZADA DA FROTA ATIVA (5.020 VEÍCULOS) ===")
for r in cur.fetchall():
    print(f"• {r[0]}: {r[1]} veículos ({r[2]}%)")

conn.close()
