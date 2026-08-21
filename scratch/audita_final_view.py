#!/usr/bin/env python3
"""
Auditoria Final de Consistência e Cobertura (01/08/2026 a 19/08/2026)
"""
import os
import psycopg2
from dotenv import load_dotenv

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

conn = psycopg2.connect(host='192.168.0.37', port=5433, database='dw', user='gabriel_brittes', password=os.getenv('DW_PASSWORD'))
cur = conn.cursor()

print("="*80)
print("1. RESUMO GERAL NA VIEW OFICIAL TORRE.VW_ALERTAS_TELEMETRIA_SANEADOS (ÚLTIMAS 2 SEMANAS)")
print("="*80)
cur.execute("""
    SELECT 
        provedor_rastreador,
        COUNT(*) AS total_alertas,
        COUNT(DISTINCT placa) AS total_veiculos,
        MAX(velocidade_registrada) AS vel_max,
        ROUND(AVG(velocidade_registrada)::numeric, 1) AS vel_media
    FROM torre.vw_alertas_telemetria_saneados
    WHERE data_hora_timestamp >= '2026-08-01 00:00:00'::timestamp
      AND data_hora_timestamp <= '2026-08-19 23:59:59'::timestamp
    GROUP BY provedor_rastreador
    ORDER BY total_alertas DESC;
""")
rows = cur.fetchall()
total_ev = 0
for r in rows:
    total_ev += r[1]
    print(f"  📡 Provedor: {r[0]:10} -> {r[1]:5} alertas | {r[2]:3} veículos | Pico: {r[3]:.0f} km/h | Média: {r[4]} km/h")

print(f"\n  🎯 TOTAL DE EVENTOS CONSOLIDADOS NO PERÍODO: {total_ev}")

print("\n" + "="*80)
print("2. DISTRIBUIÇÃO DIÁRIA (01/08 A 19/08) NA VIEW SANEADA")
print("="*80)
cur.execute("""
    SELECT 
        data_ref,
        COUNT(CASE WHEN provedor_rastreador = 'NUXEO' THEN 1 END) AS nuxeo_alertas,
        COUNT(CASE WHEN provedor_rastreador = 'OMNILINK' THEN 1 END) AS omnilink_alertas,
        COUNT(CASE WHEN provedor_rastreador = '3STEC' THEN 1 END) AS tres_s_alertas,
        COUNT(*) AS total_dia,
        COUNT(DISTINCT placa) AS veiculos_dia
    FROM torre.vw_alertas_telemetria_saneados
    WHERE data_ref >= '2026-08-01' AND data_ref <= '2026-08-19'
    GROUP BY data_ref
    ORDER BY data_ref ASC;
""")
for r in cur.fetchall():
    print(f"  📅 {r[0]}: Total={r[4]:3} alertas ({r[5]:2} veículos) | NUXEO={r[1]:3} | OMNILINK={r[2]:3} | 3STEC={r[3]:2}")

cur.close()
conn.close()
