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

print("Criando estrutura no DW para importação de planilhas da PÓSITRON e outros fornecedores Excel...")

# 1. Tabela Bronze de Ingestão de Planilhas
cur.execute("""
CREATE TABLE IF NOT EXISTS bronze.positron_veiculos_planilha (
    id SERIAL PRIMARY KEY,
    placa VARCHAR(20) NOT NULL,
    serial_equipamento VARCHAR(50),
    modelo_rastreador VARCHAR(100),
    cliente_contrato VARCHAR(150),
    filial VARCHAR(100),
    status_rastreador VARCHAR(50),
    nome_arquivo VARCHAR(255),
    ingested_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Procedure para processar e atualizar torre.map_veiculo_rastreador
CREATE OR REPLACE FUNCTION bronze.fn_processa_planilha_positron(p_nome_arquivo TEXT DEFAULT 'Carga Manual')
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE v_linhas INT;
BEGIN
    INSERT INTO torre.map_veiculo_rastreador (
        placa,
        provedor_rastreador,
        origem_mapeamento,
        observacao,
        atualizado_em
    )
    SELECT DISTINCT 
        UPPER(REPLACE(REPLACE(p.placa, '-', ''), ' ', '')) AS placa,
        'POSITRON' AS provedor_rastreador,
        'EXCEL' AS origem_mapeamento,
        'Importado via Planilha Pósitron (' || COALESCE(p_nome_arquivo, 'Excel') || ')' AS observacao,
        NOW()
    FROM bronze.positron_veiculos_planilha p
    JOIN torre.gold_dim_veiculo v ON UPPER(REPLACE(v.placa, '-', '')) = UPPER(REPLACE(REPLACE(p.placa, '-', ''), ' ', ''))
    WHERE v.situacao_veiculo NOT IN ('VENDIDO', 'BAIXADO')
    ON CONFLICT (placa, provedor_rastreador) DO UPDATE SET
        origem_mapeamento = 'EXCEL',
        observacao = EXCLUDED.observacao,
        atualizado_em = NOW();

    GET DIAGNOSTICS v_linhas = ROW_COUNT;
    RETURN v_linhas;
END;
$$;
""")

conn.commit()
print("✅ Tabela bronze.positron_veiculos_planilha e função fn_processa_planilha_positron criadas com SUCESSO!")
conn.close()
