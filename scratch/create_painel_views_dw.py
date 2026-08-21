import psycopg2, os
from dotenv import load_dotenv

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

conn = psycopg2.connect(
    host='192.168.0.37',
    port=5433,
    database=os.getenv('DW_NAME'),
    user=os.getenv('DW_USER'),
    password=os.getenv('DW_PASSWORD')
)
cur = conn.cursor()

# Safe timestamp converter function
cur.execute("""
CREATE OR REPLACE FUNCTION torre.fn_safe_to_timestamp(p_str TEXT)
RETURNS TIMESTAMP WITH TIME ZONE
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_str IS NULL OR TRIM(p_str) = '' THEN
        RETURN NULL;
    END IF;
    -- Try DD/MM/YYYY HH24:MI:SS
    BEGIN
        RETURN to_timestamp(TRIM(p_str), 'DD/MM/YYYY HH24:MI:SS');
    EXCEPTION WHEN OTHERS THEN
        BEGIN
            RETURN to_timestamp(TRIM(p_str), 'YYYY-MM-DD HH24:MI:SS');
        EXCEPTION WHEN OTHERS THEN
            RETURN NULL;
        END;
    END;
END;
$$;
""")
conn.commit()

print("Recriando View torre.vw_painel_frota_consolidada...")

cur.execute("""
CREATE OR REPLACE VIEW torre.vw_painel_frota_consolidada AS
WITH ult_sinal_nuxeo AS (
    SELECT 
        UPPER(REPLACE(placa, '-', '')) AS placa,
        MAX(torre.fn_safe_to_timestamp(data_gps)) AS data_ultimo_sinal
    FROM bronze.nuxeo_veiculos_posicao
    GROUP BY UPPER(REPLACE(placa, '-', ''))
),
ult_sinal_3s AS (
    SELECT 
        UPPER(REPLACE(placa, '-', '')) AS placa,
        MAX(torre.fn_safe_to_timestamp(data_gps)) AS data_ultimo_sinal
    FROM bronze.tres_s_ultima_posicao
    GROUP BY UPPER(REPLACE(placa, '-', ''))
),
sinais_consolidados AS (
    SELECT 
        COALESCE(n.placa, s.placa) AS placa,
        GREATEST(n.data_ultimo_sinal, s.data_ultimo_sinal) AS data_ultimo_sinal
    FROM ult_sinal_nuxeo n
    FULL OUTER JOIN ult_sinal_3s s ON s.placa = n.placa
),
ult_hist_planilha AS (
    SELECT DISTINCT ON (UPPER(REPLACE(placa, '-', '')))
        UPPER(REPLACE(placa, '-', '')) AS placa,
        km_periodo,
        status_comunicacao,
        data_importacao,
        semana_ano
    FROM bronze.hist_planilha_rastreador
    ORDER BY UPPER(REPLACE(placa, '-', '')), data_importacao DESC, id DESC
),
rastreadores_agrupados AS (
    SELECT 
        m.placa,
        COUNT(DISTINCT m.provedor_rastreador) AS qtd_rastreadores,
        STRING_AGG(DISTINCT m.provedor_rastreador, ' + ' ORDER BY m.provedor_rastreador) AS rastreadores_instalados,
        BOOL_OR(m.provedor_rastreador IN ('3STEC', 'NUXEO', 'OMNILINK')) AS tem_api,
        BOOL_OR(m.provedor_rastreador IN ('POSITRON', 'SASCAR', 'T4S', 'AVANSAT', 'GR PARCERIA')) AS tem_planilha
    FROM torre.map_veiculo_rastreador m
    GROUP BY m.placa
)
SELECT 
    v.placa,
    v.modelo_raw AS modelo,
    v.grupo_veiculo,
    v.filial_operacional,
    v.situacao_veiculo,
    CASE 
        WHEN v.filial_operacional ILIKE 'GRITSCH%' THEN 'GRITSCH'
        WHEN v.filial_operacional ILIKE 'REFERÊNCIA%' OR v.filial_operacional ILIKE 'REFERENCIA%' THEN 'REFERÊNCIA'
        ELSE 'OUTROS'
    END AS empresa,
    COALESCE(r.qtd_rastreadores, 0) AS qtd_rastreadores,
    COALESCE(r.rastreadores_instalados, 'PENDENTE DE MAPEAMENTO') AS rastreadores_instalados,
    COALESCE(r.qtd_rastreadores > 1, FALSE) AS possui_multi_rastreador,
    
    -- Status de Telemetria / Comunicação
    CASE 
        WHEN r.rastreadores_instalados IS NULL THEN 'SEM_RASTREADOR'
        WHEN r.tem_api AND sc.data_ultimo_sinal >= NOW() - INTERVAL '48 hours' THEN 'ONLINE'
        WHEN r.tem_api AND (sc.data_ultimo_sinal < NOW() - INTERVAL '48 hours' OR sc.data_ultimo_sinal IS NULL) THEN 'SEM_SINAL_48H'
        WHEN NOT r.tem_api AND hp.km_periodo > 0 THEN 'DECLARADO_EM_MOVIMENTO'
        WHEN NOT r.tem_api AND (hp.km_periodo = 0 OR hp.km_periodo IS NULL) THEN 'DECLARADO_ZERADO'
        ELSE 'DECLARADO_PLANILHA'
    END AS status_telemetria,
    
    sc.data_ultimo_sinal,
    hp.km_periodo AS km_ultima_semana,
    hp.data_importacao AS data_ultima_planilha,
    
    -- Gestão de Vistorias e Tratativas
    vis.motivo_ocorrencia AS motivo_vistoria,
    vis.status_tratativa AS status_vistoria,
    vis.observacao AS obs_vistoria,
    vis.responsavel AS responsavel_vistoria,
    vis.atualizado_em AS data_vistoria,
    (vis.id IS NOT NULL) AS vistoriado

FROM torre.gold_dim_veiculo v
LEFT JOIN rastreadores_agrupados r ON r.placa = UPPER(REPLACE(v.placa, '-', ''))
LEFT JOIN sinais_consolidados sc ON sc.placa = UPPER(REPLACE(v.placa, '-', ''))
LEFT JOIN ult_hist_planilha hp ON hp.placa = UPPER(REPLACE(v.placa, '-', ''))
LEFT JOIN torre.gestao_vistoria_veiculo vis ON vis.placa = UPPER(REPLACE(v.placa, '-', ''))
WHERE v.situacao_veiculo NOT IN ('VENDIDO', 'BAIXADO');
""")

conn.commit()
print("✅ View torre.vw_painel_frota_consolidada criada com SUCESSO!")
conn.close()
