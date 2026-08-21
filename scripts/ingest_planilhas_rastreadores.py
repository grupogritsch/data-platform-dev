#!/usr/bin/env python3
"""
Ingestão e Processamento das Planilhas de Rastreadores (Pósitron, Sascar, T4S, Avansat, GR Parceria)
Carrega os dados brutos no staging bronze.import_planilha_rastreador e atualiza a torre.map_veiculo_rastreador.
"""

import os
import re
import psycopg2
import pandas as pd
from dotenv import load_dotenv

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

FOLDER = '/home/gabriel/Projetos/data-platform-dev/documentacao/planilhas_rastreadores'

def clean_plate(p):
    if not p or pd.isna(p):
        return None
    s = re.sub(r'[^A-Z0-9]', '', str(p).upper().strip())
    if len(s) == 7:
        return s
    return None

def main():
    print("=== INÍCIO DA INGESTÃO DAS PLANILHAS DE RASTREADORES NO DW ===\n")

    conn = psycopg2.connect(
        host='192.168.0.37',
        port=5433,
        database=os.getenv('DW_NAME'),
        user=os.getenv('DW_USER'),
        password=os.getenv('DW_PASSWORD')
    )
    cur = conn.cursor()

    # 1. Limpar staging de importação
    cur.execute("TRUNCATE TABLE bronze.import_planilha_rastreador;")
    conn.commit()
    print("1. Staging bronze.import_planilha_rastreador limpo.")

    records_to_insert = []

    # ========================================================
    # 2. PROCESSAR POSITRON
    # ========================================================
    file_pos = 'Relatorio Positron 17082026.xls'
    path_pos = os.path.join(FOLDER, file_pos)
    if os.path.exists(path_pos):
        df_pos = pd.read_excel(path_pos, header=None)
        for _, row in df_pos.iloc[3:].iterrows():
            placa = clean_plate(row.iloc[2])
            if placa:
                records_to_insert.append((
                    placa,
                    'POSITRON',
                    'RASTREADOR',
                    None,
                    None,
                    None,
                    file_pos
                ))
        print(f"• Pósitron: {len([r for r in records_to_insert if r[1] == 'POSITRON'])} registros preparados.")

    # ========================================================
    # 3. PROCESSAR SASCAR
    # ========================================================
    file_sas = 'SASCAR 17082026.xlsx'
    path_sas = os.path.join(FOLDER, file_sas)
    if os.path.exists(path_sas):
        df_sas = pd.read_excel(path_sas, header=7, engine='openpyxl')
        for _, row in df_sas.iterrows():
            placa = clean_plate(row.iloc[0])
            if placa:
                records_to_insert.append((
                    placa,
                    'SASCAR',
                    'RASTREADOR',
                    None,
                    None,
                    None,
                    file_sas
                ))
        print(f"• Sascar: {len([r for r in records_to_insert if r[1] == 'SASCAR'])} registros preparados.")

    # ========================================================
    # 4. PROCESSAR T4S (BLOQUEADOR)
    # ========================================================
    file_t4s = 'T4S 17082026.xlsx'
    path_t4s = os.path.join(FOLDER, file_t4s)
    if os.path.exists(path_t4s):
        df_t4s = pd.read_excel(path_t4s, engine='openpyxl')
        for _, row in df_t4s.iterrows():
            placa = clean_plate(row['Placa'])
            desc = str(row.get('Descricao', ''))
            if placa:
                records_to_insert.append((
                    placa,
                    'T4S',
                    'BLOQUEADOR',
                    None,
                    desc,
                    None,
                    file_t4s
                ))
        print(f"• T4S (Bloqueador): {len([r for r in records_to_insert if r[1] == 'T4S'])} registros preparados.")

    # ========================================================
    # 5. PROCESSAR AVANSAT (CÂMERAS)
    # ========================================================
    file_avan = 'AVANSAT 17082026.xlsx'
    path_avan = os.path.join(FOLDER, file_avan)
    if os.path.exists(path_avan):
        df_avan = pd.read_excel(path_avan, header=6, engine='openpyxl')
        for _, row in df_avan.iterrows():
            placa = clean_plate(row.iloc[2])
            localidade = str(row.iloc[1]) if pd.notna(row.iloc[1]) else None
            if placa:
                records_to_insert.append((
                    placa,
                    'AVANSAT',
                    'CAMERA',
                    None,
                    'Câmera Veicular',
                    localidade,
                    file_avan
                ))
        print(f"• Avansat (Câmeras): {len([r for r in records_to_insert if r[1] == 'AVANSAT'])} registros preparados.")

    # ========================================================
    # 6. PROCESSAR GR PARCERIA (GERENCIADORA DE RISCO)
    # ========================================================
    file_gr = 'Relatorio GR PARCERIA 17082026.xls'
    path_gr = os.path.join(FOLDER, file_gr)
    if os.path.exists(path_gr):
        df_gr = pd.read_excel(path_gr, header=None)
        # Identificar se veio de coluna Autotrac ou Omnilink
        col_autotrac = 0
        col_omnilink = 4 if df_gr.shape[1] > 4 else 1
        for col_idx in range(df_gr.shape[1]):
            for val in df_gr.iloc[:, col_idx]:
                placa = clean_plate(val)
                if placa:
                    tech = 'GR (AUTOTRAC)' if col_idx < 3 else 'GR (OMNILINK)'
                    records_to_insert.append((
                        placa,
                        'GR PARCERIA',
                        tech,
                        None,
                        'Gerenciadora de Risco',
                        None,
                        file_gr
                    ))
        print(f"• GR Parceria: {len([r for r in records_to_insert if r[1] == 'GR PARCERIA'])} registros preparados.")

    # ========================================================
    # 7. INSERIR NO STAGING DO DW
    # ========================================================
    insert_sql = """
        INSERT INTO bronze.import_planilha_rastreador 
        (placa, provedor_rastreador, tipo_tecnologia, serial_equipamento, modelo_equipamento, filial_planilha, nome_arquivo)
        VALUES (%s, %s, %s, %s, %s, %s, %s);
    """
    cur.executemany(insert_sql, records_to_insert)
    conn.commit()
    print(f"\n2. Total de {len(records_to_insert)} registros inseridos em bronze.import_planilha_rastreador.")

    # ========================================================
    # 8. EXECUTAR PROCEDURE DE CRUZAMENTO E MAPEAMENTO NO DW
    # ========================================================
    print("\n3. Executando procedimento de enriquecimento na torre.map_veiculo_rastreador...")
    cur.execute("SELECT * FROM bronze.fn_processa_planilhas_rastreador();")
    res = cur.fetchall()
    print("--- RESULTADO DO PROCESSAMENTO POR PROVEDOR ---")
    for r in res:
        print(f"• Provedor: {r[0]:<15} | Linhas Processadas: {r[1]} | Placas Ativas Vinculadas: {r[2]}")

    conn.commit()

    # ========================================================
    # 9. AUDITORIA GERAL DA FROTA ATIVA
    # ========================================================
    print("\n" + "="*70)
    print("🏆 AUDITORIA FINAL CONSOLIDADA DA FROTA ATIVA (5.019 VEÍCULOS)")
    print("="*70)
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
    for r in cur.fetchall():
        print(f"  • {r[0]}: {r[1]} veículos ({r[2]}%)")

    cur.execute("""
        SELECT 
            COUNT(*) FILTER (WHERE rastreadores_instalados <> 'PENDENTE DE MAPEAMENTO') AS total_mapeados,
            COUNT(*) FILTER (WHERE rastreadores_instalados = 'PENDENTE DE MAPEAMENTO') AS pendentes,
            COUNT(*) AS total_frota,
            ROUND(COUNT(*) FILTER (WHERE rastreadores_instalados <> 'PENDENTE DE MAPEAMENTO') * 100.0 / COUNT(*), 1) AS perc_mapeado
        FROM torre.vw_veiculo_rastreador_consolidado
        WHERE situacao_veiculo NOT IN ('VENDIDO', 'BAIXADO');
    """)
    t_map, t_pend, t_total, t_perc = cur.fetchone()
    print(f"\n🎯 BALANÇO GERAL: {t_map} de {t_total} veículos ativos mapeados ({t_perc}% DA FROTA TOTAL)!")

    conn.close()

if __name__ == '__main__':
    main()
