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

sql = """
CREATE OR REPLACE FUNCTION torre.fn_processa_alertas_3s()
RETURNS INTEGER
LANGUAGE plpgsql
AS $func$
DECLARE 
    v_linhas INT;
BEGIN
    INSERT INTO torre.log_alerta_rastreador (
        placa,
        velocidade_registrada,
        velocidade_permitida,
        excesso_kmh,
        data_hora_alerta,
        latitude,
        longitude,
        filial_operacional,
        modelo,
        situacao_veiculo,
        cidade,
        estado,
        endereco,
        data_ref,
        nome_evento,
        criado_em
    )
    SELECT 
        UPPER(REPLACE(v.placa, '-', '')) AS placa,
        NULLIF(e.velocidade, '')::NUMERIC AS velocidade_registrada,
        NULLIF(e.velocidade_limite, '')::NUMERIC AS velocidade_permitida,
        (NULLIF(e.velocidade, '')::NUMERIC - NULLIF(e.velocidade_limite, '')::NUMERIC) AS excesso_kmh,
        e.data_evento AS data_hora_alerta,
        e.latitude,
        e.longitude,
        v.filial_operacional,
        v.modelo_raw AS modelo,
        v.situacao_veiculo,
        e.cidade,
        e.uf AS estado,
        e.endereco,
        TO_CHAR(TO_TIMESTAMP(e.data_evento, 'DD/MM/YYYY HH24:MI:SS'), 'DD/MM/YYYY') AS data_ref,
        COALESCE(v.grupo_veiculo, '3S') || ' Excesso Velocidade' AS nome_evento,
        NOW()
    FROM bronze.tres_s_eventos e
    JOIN bronze.tres_s_veiculos tv ON tv.id_equipamento = e.id_equipamento
    JOIN torre.gold_dim_veiculo v ON UPPER(REPLACE(v.placa, '-', '')) = UPPER(REPLACE(tv.placa, '-', ''))
    WHERE e.tipo_evento = 'ALERTA_VELOCIDADE';

    GET DIAGNOSTICS v_linhas = ROW_COUNT;
    RETURN v_linhas;
END;
$func$;
"""

cur.execute(sql)
conn.commit()
print("✅ Função torre.fn_processa_alertas_3s criada com SUCESSO no DW!")
conn.close()
