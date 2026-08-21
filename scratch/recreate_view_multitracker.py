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

print("Recriando a View Consolidada torre.vw_veiculo_rastreador_consolidado...")
cur.execute("DROP VIEW IF EXISTS torre.vw_veiculo_rastreador_consolidado CASCADE;")

cur.execute("""
    CREATE VIEW torre.vw_veiculo_rastreador_consolidado AS
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
print("✅ View torre.vw_veiculo_rastreador_consolidado recriada com SUCESSO TOTAL!")

# Test query
cur.execute("""
    SELECT 
        rastreadores_instalados,
        COUNT(*) AS total_veiculos,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percentual
    FROM torre.vw_veiculo_rastreador_consolidado
    WHERE situacao_veiculo NOT IN ('VENDIDO', 'BAIXADO')
    GROUP BY rastreadores_instalados
    ORDER BY total_veiculos DESC;
""")

print("\n=== DISTRIBUIÇÃO ATUALIZADA DA FROTA ATIVA (5.020 VEÍCULOS) ===")
for r in cur.fetchall():
    print(f"• {r[0]}: {r[1]} veículos ({r[2]}%)")

conn.close()
