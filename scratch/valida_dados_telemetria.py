#!/usr/bin/env python3
"""
Validação e Diagnóstico de Dados de Telemetria — Últimas 2 Semanas
Conecta no DW PostgreSQL e analisa o comportamento das regras de saneamento.
"""

import os
import sys
import psycopg2
from dotenv import load_dotenv

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

def get_connection():
    hosts = [os.getenv('DW_HOST', '192.168.0.37'), 'localhost', '127.0.0.1']
    for host in hosts:
        try:
            conn = psycopg2.connect(
                host=host,
                port=int(os.getenv('DW_PORT', 5433)),
                database=os.getenv('DW_NAME', 'dw'),
                user=os.getenv('DW_USER', 'gabriel_brittes'),
                password=os.getenv('DW_PASSWORD'),
                connect_timeout=3
            )
            print(f"✅ Conectado ao DW com sucesso no host: {host}")
            return conn
        except Exception as e:
            print(f"⚠️ Falha ao conectar no host {host}: {e}")
    raise Exception("Não foi possível conectar ao DW em nenhum dos hosts.")

def main():
    conn = get_connection()
    cur = conn.cursor()

    # 1. Aplicar o DDL das tabelas de email e views
    print("\n" + "="*80)
    print("1. APLICANDO/ATUALIZANDO TABELAS DE EMAIL E VIEWS DE TELEMETRIA NO DW...")
    print("="*80)
    try:
        sql_emails_path = '/home/gabriel/Projetos/data-platform-dev/postgres/sql/setup_email_gritsch_filiais.sql'
        with open(sql_emails_path, 'r') as f:
            sql_emails = f.read()
        cur.execute(sql_emails)
        conn.commit()
        print("✅ Tabelas torre.email_gritsch_filiais e torre.email_gritsch_config criadas/atualizadas com sucesso!")

        sql_views_path = '/home/gabriel/Projetos/data-platform-dev/postgres/sql/torre_views_alertas_telemetria.sql'
        with open(sql_views_path, 'r') as f:
            sql_views = f.read()
        cur.execute(sql_views)
        conn.commit()
        print("✅ Views torre.vw_alertas_telemetria_saneados e torre.vw_telemetria_anomalias_descartadas aplicadas!")
    except Exception as e:
        conn.rollback()
        print(f"⚠️ Erro ao aplicar DDL/Views: {e}")

    # 2. Verificar volumetria bruta nas últimas 2 semanas (05/08 a 19/08)
    print("\n" + "="*80)
    print("2. VOLUMETRIA BRUTA NAS TABELAS DE ORIGEM (ÚLTIMAS 2 SEMANAS)")
    print("="*80)
    
    # NUXEO
    cur.execute("""
        SELECT 
            COUNT(*) AS total_registros,
            COUNT(DISTINCT t.placa) AS qtd_placas,
            MIN(t.ingested_at) AS min_ingest,
            MAX(t.ingested_at) AS max_ingest
        FROM bronze.nuxeo_posicao_eventos t
        WHERE t.ingested_at >= CURRENT_DATE - INTERVAL '14 days';
    """)
    res_nuxeo = cur.fetchone()
    print(f"📦 bronze.nuxeo_posicao_eventos: {res_nuxeo[0]} registros, {res_nuxeo[1]} placas distintas (Ingestão de {res_nuxeo[2]} até {res_nuxeo[3]})")

    # 3STEC
    try:
        cur.execute("""
            SELECT 
                COUNT(*) AS total_eventos,
                COUNT(DISTINCT e.id_equipamento) AS qtd_equipamentos
            FROM bronze.tres_s_eventos e
            WHERE to_timestamp(e.data_evento, 'DD/MM/YYYY HH24:MI:SS') >= CURRENT_DATE - INTERVAL '14 days';
        """)
        res_3s = cur.fetchone()
        print(f"📦 bronze.tres_s_eventos (3STEC): {res_3s[0]} eventos, {res_3s[1]} equipamentos distintos")
    except Exception as e:
        conn.rollback()
        print(f"📦 bronze.tres_s_eventos: {e}")

    # 3. Análise de Saneamento: Válidos vs Anomalias Descartadas
    print("\n" + "="*80)
    print("3. RESULTADO DO SANEAMENTO (ÚLTIMAS 2 SEMANAS)")
    print("="*80)
    
    cur.execute("""
        SELECT 
            COUNT(*) AS total_alertas_saneados,
            COUNT(DISTINCT placa) AS qtd_placas_saneadas,
            ROUND(AVG(velocidade_registrada)::numeric, 1) AS vel_media,
            MAX(velocidade_registrada) AS vel_maxima,
            MIN(velocidade_registrada) AS vel_minima
        FROM torre.vw_alertas_telemetria_saneados
        WHERE data_hora_timestamp >= CURRENT_DATE - INTERVAL '14 days';
    """)
    saneados = cur.fetchone()
    print(f"✅ ALERTAS VÁLIDOS / SANEADOS:")
    print(f"   - Total de Eventos: {saneados[0]}")
    print(f"   - Veículos Distintos: {saneados[1]}")
    print(f"   - Velocidade Média: {saneados[2]} km/h")
    print(f"   - Velocidade Máxima: {saneados[3]} km/h")
    print(f"   - Velocidade Mínima: {saneados[4]} km/h")

    cur.execute("""
        SELECT 
            motivo_descarte,
            COUNT(*) AS qtd_descartada,
            COUNT(DISTINCT placa) AS qtd_placas,
            MIN(velocidade_registrada) AS vel_min,
            MAX(velocidade_registrada) AS vel_max
        FROM torre.vw_telemetria_anomalias_descartadas
        WHERE data_hora_timestamp >= CURRENT_DATE - INTERVAL '14 days'
        GROUP BY motivo_descarte
        ORDER BY qtd_descartada DESC;
    """)
    anomalias = cur.fetchall()
    print(f"\n🚫 ANOMALIAS DESCARTADAS POR MOTIVO:")
    if anomalias:
        for a in anomalias:
            print(f"   - {a[0]}: {a[1]} registros ({a[2]} placas) | Vel: {a[3]} a {a[4]} km/h")
    else:
        print("   - Nenhuma anomalia encontrada no período.")

    # 4. Amostra de Anomalias Descartadas (Ex: pontos sombra > 160 e caminhões > 120)
    print("\n" + "="*80)
    print("4. AMOSTRA DE ANOMALIAS DESCARTADAS (DETALHE)")
    print("="*80)
    cur.execute("""
        SELECT 
            placa,
            provedor_rastreador,
            velocidade_registrada,
            modelo,
            grupo_veiculo,
            filial_operacional,
            data_hora_alerta,
            cidade,
            motivo_descarte
        FROM torre.vw_telemetria_anomalias_descartadas
        WHERE data_hora_timestamp >= CURRENT_DATE - INTERVAL '14 days'
        ORDER BY velocidade_registrada DESC
        LIMIT 10;
    """)
    amostras_anomalias = cur.fetchall()
    for am in amostras_anomalias:
        print(f"   🚗 {am[0]} ({am[1]}) | {am[2]} km/h | {am[3]} ({am[4]}) | Filial: {am[5]} | Data: {am[6]} | Motivo: {am[8]}")

    # 5. Distribuição de Eventos Válidos por Provedor de Rastreamento
    print("\n" + "="*80)
    print("5. DISTRIBUIÇÃO DE ALERTAS POR PROVEDOR (ORIGEM DA INFORMAÇÃO)")
    print("="*80)
    cur.execute("""
        SELECT 
            provedor_rastreador,
            COUNT(*) AS total_alertas,
            COUNT(DISTINCT placa) AS qtd_placas,
            ROUND(AVG(velocidade_registrada)::numeric, 1) AS vel_media,
            MAX(velocidade_registrada) AS vel_max
        FROM torre.vw_alertas_telemetria_saneados
        WHERE data_hora_timestamp >= CURRENT_DATE - INTERVAL '14 days'
        GROUP BY provedor_rastreador
        ORDER BY total_alertas DESC;
    """)
    por_provedor = cur.fetchall()
    for p in por_provedor:
        print(f"   📡 {p[0]}: {p[1]} alertas | {p[2]} placas | Média: {p[3]} km/h | Pico: {p[4]} km/h")

    # 6. Distribuição de Eventos por Filial Operacional
    print("\n" + "="*80)
    print("6. DISTRIBUIÇÃO DE ALERTAS POR FILIAL (ÚLTIMAS 2 SEMANAS)")
    print("="*80)
    cur.execute("""
        SELECT 
            filial_operacional,
            COUNT(*) AS total_alertas,
            COUNT(DISTINCT placa) AS qtd_placas,
            MAX(velocidade_registrada) AS vel_max,
            ROUND(AVG(velocidade_registrada)::numeric, 1) AS vel_media
        FROM torre.vw_alertas_telemetria_saneados
        WHERE data_hora_timestamp >= CURRENT_DATE - INTERVAL '14 days'
        GROUP BY filial_operacional
        ORDER BY total_alertas DESC;
    """)
    por_filial = cur.fetchall()
    for f in por_filial:
        print(f"   🏢 {f[0]}: {f[1]} alertas | {f[2]} placas | Pico: {f[3]} km/h | Média: {f[4]} km/h")

    # 7. Top 10 Maiores Velocidades Válidas
    print("\n" + "="*80)
    print("7. TOP 10 MAIORES VELOCIDADES VÁLIDAS (PÓS-SANEAMENTO)")
    print("="*80)
    cur.execute("""
        SELECT 
            placa,
            provedor_rastreador,
            velocidade_registrada,
            modelo,
            grupo_veiculo,
            filial_operacional,
            data_hora_alerta,
            cidade,
            estado
        FROM torre.vw_alertas_telemetria_saneados
        WHERE data_hora_timestamp >= CURRENT_DATE - INTERVAL '14 days'
        ORDER BY velocidade_registrada DESC
        LIMIT 10;
    """)
    top_vel = cur.fetchall()
    for tv in top_vel:
        print(f"   ⚡ {tv[0]} ({tv[1]}) | {tv[2]} km/h | {tv[3]} ({tv[4]}) | Filial: {tv[5]} | {tv[7]}/{tv[8]} | Data: {tv[6]}")

    # 8. Veículos Mais Recidivistas (Mais Alertas nas 2 semanas)
    print("\n" + "="*80)
    print("8. TOP 10 VEÍCULOS COM MAIS ALERTAS (RECIDIVISTAS)")
    print("="*80)
    cur.execute("""
        SELECT 
            placa,
            provedor_rastreador,
            COUNT(*) AS total_alertas,
            MAX(velocidade_registrada) AS vel_max,
            modelo,
            grupo_veiculo,
            filial_operacional
        FROM torre.vw_alertas_telemetria_saneados
        WHERE data_hora_timestamp >= CURRENT_DATE - INTERVAL '14 days'
        GROUP BY placa, provedor_rastreador, modelo, grupo_veiculo, filial_operacional
        ORDER BY total_alertas DESC
        LIMIT 10;
    """)
    top_recid = cur.fetchall()
    for tr in top_recid:
        print(f"   🚨 {tr[0]} ({tr[1]}) | {tr[2]} alertas | Pico: {tr[3]} km/h | {tr[4]} ({tr[5]}) | Filial: {tr[6]}")

    # 9. Validação de E-mails Vinculados
    print("\n" + "="*80)
    print("9. VALIDAÇÃO DE FILIAIS COM EVENTOS VS E-MAILS CADASTRADOS")
    print("="*80)
    cur.execute("""
        SELECT DISTINCT
            s.filial_operacional,
            ef.email_destino,
            ef.cc_regional,
            CASE WHEN ef.email_destino IS NOT NULL THEN '✅ OK' ELSE '⚠️ SEM E-MAIL NO BANCO' END AS status_email
        FROM torre.vw_alertas_telemetria_saneados s
        LEFT JOIN torre.email_gritsch_filiais ef ON ef.filial_operacional = s.filial_operacional
        WHERE s.data_hora_timestamp >= CURRENT_DATE - INTERVAL '14 days'
        ORDER BY status_email, s.filial_operacional;
    """)
    check_emails = cur.fetchall()
    for ce in check_emails:
        print(f"   {ce[3]} | {ce[0]} -> Destino: {ce[1]} | Regional: {ce[2]}")

    cur.close()
    conn.close()
    print("\n" + "="*80)
    print("✅ VALIDAÇÃO CONCLUÍDA COM SUCESSO!")
    print("="*80)

if __name__ == '__main__':
    main()
