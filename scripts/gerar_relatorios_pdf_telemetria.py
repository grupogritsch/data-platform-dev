#!/usr/bin/env python3
"""
Gerador de Relatórios de Telemetria em PDF — Modelo Limpo Sequencial (Tabelas Empilhadas)
Padrão Executivo Transportes Gritsch
- Filial: 1 Página A4 (Tabelas 100% de largura sequenciais)
- Consolidado Diretoria: 2 Páginas A4 (Tabelas 100% de largura sequenciais)
"""

import os
import psycopg2
import fitz  # PyMuPDF
from datetime import datetime
from dotenv import load_dotenv
from weasyprint import HTML

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

OUTPUT_DIR = '/home/gabriel/Projetos/data-platform-dev/relatorios'
ARTIFACT_DIR = '/home/gabriel/.gemini/antigravity-cli/brain/07f56712-a529-4baa-ac39-def335e84213'
LOGO_PATH = os.path.join(OUTPUT_DIR, 'logo_gritsch.png')

os.makedirs(OUTPUT_DIR, exist_ok=True)

def get_connection():
    return psycopg2.connect(
        host=os.getenv('DW_HOST', '192.168.0.37'),
        port=int(os.getenv('DW_PORT', 5433)),
        database=os.getenv('DW_NAME', 'dw'),
        user=os.getenv('DW_USER', 'gabriel_brittes'),
        password=os.getenv('DW_PASSWORD')
    )

CSS_CLEAN_STACKED_STYLES = """
@page {
    size: A4 portrait;
    margin: 8mm 10mm 8mm 10mm;
    @bottom-right {
        content: "Página " counter(page) " de " counter(pages);
        font-family: Arial, sans-serif;
        font-size: 6.5pt;
        color: #6B7280;
    }
    @bottom-left {
        content: "Transportes Gritsch | Torre de Controle — Relatório Oficial de Telemetria";
        font-family: Arial, sans-serif;
        font-size: 6.5pt;
        color: #6B7280;
    }
}

body {
    font-family: Arial, Helvetica, sans-serif;
    color: #1F2937;
    margin: 0;
    padding: 0;
    font-size: 7pt;
    line-height: 1.2;
    background: #FFFFFF;
}

/* CABEÇALHO */
.header-table {
    width: 100%;
    border-collapse: collapse;
    border-bottom: 2px solid #1E3A5F;
    padding-bottom: 4px;
    margin-bottom: 6px;
}
.header-table td {
    vertical-align: middle;
}
.logo-img {
    width: 95px;
    max-width: 95px;
    height: auto;
    max-height: 26px;
    display: block;
}
.header-title {
    text-align: right;
}
.header-title h1 {
    font-size: 10.5pt;
    font-weight: bold;
    color: #1E3A5F;
    margin: 0;
}
.header-title p {
    font-size: 6.5pt;
    color: #4B5563;
    margin: 1px 0 0 0;
}

/* TÍTULOS DE SEÇÃO */
.section-header {
    font-size: 7.2pt;
    font-weight: bold;
    color: #1E3A5F;
    text-transform: uppercase;
    letter-spacing: 0.2px;
    border-bottom: 1px solid #1E3A5F;
    padding-bottom: 1.5px;
    margin: 6px 0 3px 0;
}

/* TABELAS 100% LARGURA SEQUENCIAIS */
.tbl-clean {
    width: 100%;
    border-collapse: collapse;
    margin-bottom: 5px;
    font-size: 6.6pt;
    border: 1px solid #D1D5DB;
}
.tbl-clean th {
    background-color: #F3F4F6;
    color: #111827;
    font-weight: bold;
    font-size: 6.2pt;
    text-transform: uppercase;
    padding: 2.5px 4.5px;
    border: 1px solid #D1D5DB;
    border-bottom: 1.2px solid #9CA3AF;
    text-align: left;
}
.tbl-clean th.center, .tbl-clean td.center { text-align: center; }
.tbl-clean th.right, .tbl-clean td.right { text-align: right; }
.tbl-clean td {
    padding: 2px 4.5px;
    border: 1px solid #E5E7EB;
    color: #374151;
}
.tbl-clean tr:nth-child(even) td {
    background-color: #F9FAFB;
}

/* TEXTOS E DESTAQUES */
.text-bold { font-weight: bold; }
.text-danger { color: #991B1B; font-weight: bold; }
.text-primary { color: #1E3A5F; font-weight: bold; }
.text-muted { color: #6B7280; font-size: 6.2pt; }

/* BOX INFORMATIVO SIMPLES */
.box-info {
    border: 1px solid #D1D5DB;
    background-color: #F9FAFB;
    padding: 3.5px 5px;
    font-size: 6.2pt;
    color: #374151;
    margin-top: 4px;
    border-left: 2.5px solid #1E3A5F;
    line-height: 1.15;
}

.page-break {
    page-break-before: always;
}
"""

def save_pdf_pages_as_png(pdf_path, prefix):
    doc = fitz.open(pdf_path)
    print(f"📄 {prefix} gerou {len(doc)} página(s):")
    for i, page in enumerate(doc):
        pix = page.get_pixmap(dpi=150)
        local_png = os.path.join(OUTPUT_DIR, f"{prefix}_page_{i+1}.png")
        artifact_png = os.path.join(ARTIFACT_DIR, f"{prefix}_page_{i+1}.png")
        pix.save(local_png)
        pix.save(artifact_png)
        print(f"   🖼️ Salvo: {local_png}")

def gerar_pdf_filial_goi():
    conn = get_connection()
    cur = conn.cursor()

    filial = 'GRITSCH - GOI'

    # 1. KPIs
    cur.execute("""
        SELECT 
            COUNT(*) AS total_alertas,
            COUNT(DISTINCT placa) AS qtd_veiculos,
            ROUND(AVG(velocidade_registrada)::numeric, 1) AS vel_media,
            MAX(velocidade_registrada) AS vel_max
        FROM torre.vw_alertas_telemetria_saneados
        WHERE filial_operacional = %s
          AND data_hora_timestamp >= CURRENT_DATE - INTERVAL '14 days';
    """, (filial,))
    tot_alertas, tot_veiculos, vel_media, vel_max = cur.fetchone()

    # 2. Destinatários
    cur.execute("""
        SELECT email_destino, cc_regional 
        FROM torre.email_gritsch_filiais 
        WHERE filial_operacional = %s;
    """, (filial,))
    em = cur.fetchone()
    email_dest = em[0] if em else 'goiania@gritsch.com.br'
    email_reg = em[1] if em else 'ely@gritsch.com.br'

    # 3. Veículos da filial (Top 6)
    cur.execute("""
        SELECT 
            placa,
            provedor_rastreador,
            modelo,
            grupo_veiculo,
            COUNT(*) AS qtd,
            MAX(velocidade_registrada) AS vel_pico,
            ROUND(AVG(velocidade_registrada)::numeric, 1) AS vel_media
        FROM torre.vw_alertas_telemetria_saneados
        WHERE filial_operacional = %s
          AND data_hora_timestamp >= CURRENT_DATE - INTERVAL '14 days'
        GROUP BY placa, provedor_rastreador, modelo, grupo_veiculo
        ORDER BY qtd DESC
        LIMIT 6;
    """, (filial,))
    veiculos = cur.fetchall()

    # 4. Top Ocorrências (Top 5)
    cur.execute("""
        SELECT 
            placa,
            provedor_rastreador,
            velocidade_registrada,
            data_hora_alerta,
            cidade,
            estado,
            modelo
        FROM torre.vw_alertas_telemetria_saneados
        WHERE filial_operacional = %s
          AND data_hora_timestamp >= CURRENT_DATE - INTERVAL '14 days'
        ORDER BY velocidade_registrada DESC, data_hora_timestamp DESC
        LIMIT 5;
    """, (filial,))
    ocorrencias = cur.fetchall()

    # 5. Volume por Dia (Top 5)
    cur.execute("""
        SELECT 
            data_ref::text,
            COUNT(*) AS qtd,
            MAX(velocidade_registrada) AS vel_pico,
            ROUND(AVG(velocidade_registrada)::numeric, 1) AS vel_media
        FROM torre.vw_alertas_telemetria_saneados
        WHERE filial_operacional = %s
          AND data_hora_timestamp >= CURRENT_DATE - INTERVAL '14 days'
        GROUP BY data_ref
        ORDER BY data_ref ASC
        LIMIT 5;
    """, (filial,))
    dias = cur.fetchall()

    cur.close()
    conn.close()

    rows_veiculos = ""
    for v in veiculos:
        rows_veiculos += f"""
        <tr>
            <td class="text-bold text-primary">{v[0]}</td>
            <td>{v[2] or '--'}</td>
            <td>{v[3] or 'Leve'}</td>
            <td class="center">{v[1]}</td>
            <td class="center text-bold">{v[4]}</td>
            <td class="right text-danger">{v[5]:.0f} km/h</td>
            <td class="right text-muted">{v[6]} km/h</td>
        </tr>
        """

    rows_ocorrencias = ""
    for o in ocorrencias:
        rows_ocorrencias += f"""
        <tr>
            <td class="text-bold text-primary">{o[0]}</td>
            <td>{o[6] or '--'}</td>
            <td class="center text-danger">{o[2]:.0f} km/h</td>
            <td class="center">{str(o[3])[:16]}</td>
            <td>{o[4] or ''}{('/' + o[5]) if o[5] else ''}</td>
            <td class="center">{o[1]}</td>
        </tr>
        """

    rows_dias = ""
    for d in dias:
        rows_dias += f"""
        <tr>
            <td class="center text-bold">{datetime.strptime(d[0], '%Y-%m-%d').strftime('%d/%m/%Y')}</td>
            <td class="center text-bold">{d[1]}</td>
            <td class="right text-danger">{d[2]:.0f} km/h</td>
            <td class="right text-muted">{d[3]} km/h</td>
        </tr>
        """

    html = f"""
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
        <meta charset="UTF-8">
        <title>Relatório de Telemetria — {filial}</title>
        <style>{CSS_CLEAN_STACKED_STYLES}</style>
    </head>
    <body>
        <!-- CABEÇALHO -->
        <table class="header-table">
            <tr>
                <td style="width:110px;">
                    <img src="file://{LOGO_PATH}" class="logo-img" alt="Gritsch" />
                </td>
                <td class="header-title">
                    <h1>RELATÓRIO DE TELEMETRIA & VELOCIDADE</h1>
                    <p>Unidade: <strong>{filial}</strong> | Período: <strong>05/08/2026 a 19/08/2026</strong> | Emissão: <strong>{datetime.now().strftime('%d/%m/%Y %H:%M')}</strong></p>
                    <p>Destinatário: <strong>{email_dest}</strong> | Regional: <strong>{email_reg}</strong></p>
                </td>
            </tr>
        </table>

        <!-- 1. RESUMO GERAL DA UNIDADE (TABELA) -->
        <div class="section-header">1. Resumo Consolidado da Unidade</div>
        <table class="tbl-clean">
            <thead>
                <tr>
                    <th class="center" style="width:25%;">Total de Infrações</th>
                    <th class="center" style="width:25%;">Veículos com Apontamento</th>
                    <th class="center" style="width:25%;">Velocidade Máxima</th>
                    <th class="center" style="width:25%;">Velocidade Média dos Excessos</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td class="center text-bold text-danger" style="font-size:8pt;">{tot_alertas} ocorrências</td>
                    <td class="center text-bold" style="font-size:8pt;">{tot_veiculos} veículos</td>
                    <td class="center text-bold text-danger" style="font-size:8pt;">{vel_max:.0f} km/h</td>
                    <td class="center text-bold" style="font-size:8pt;">{vel_media} km/h</td>
                </tr>
            </tbody>
        </table>

        <!-- 2. VEÍCULOS OFENSORES (TABELA SEQUENCIAL) -->
        <div class="section-header">2. Veículos com Excesso de Velocidade no Período</div>
        <table class="tbl-clean">
            <thead>
                <tr>
                    <th style="width:14%;">Placa</th>
                    <th style="width:34%;">Modelo</th>
                    <th style="width:14%;">Categoria</th>
                    <th class="center" style="width:12%;">Rastreador</th>
                    <th class="center" style="width:8%;">Qtd</th>
                    <th class="right" style="width:9%;">Pico</th>
                    <th class="right" style="width:9%;">Média</th>
                </tr>
            </thead>
            <tbody>
                {rows_veiculos}
            </tbody>
        </table>

        <!-- 3. TOP OCORRÊNCIAS MAIS GRAVES (TABELA SEQUENCIAL 100%) -->
        <div class="section-header">3. Ocorrências com Maiores Velocidades Registradas</div>
        <table class="tbl-clean">
            <thead>
                <tr>
                    <th style="width:14%;">Placa</th>
                    <th style="width:28%;">Modelo</th>
                    <th class="center" style="width:12%;">Velocidade</th>
                    <th class="center" style="width:18%;">Data / Hora</th>
                    <th style="width:18%;">Local / Município</th>
                    <th class="center" style="width:10%;">Origem</th>
                </tr>
            </thead>
            <tbody>
                {rows_ocorrencias}
            </tbody>
        </table>

        <!-- 4. DISTRIBUIÇÃO DIÁRIA (TABELA SEQUENCIAL 100%) -->
        <div class="section-header">4. Evolução do Volume por Data</div>
        <table class="tbl-clean">
            <thead>
                <tr>
                    <th class="center" style="width:30%;">Data</th>
                    <th class="center" style="width:25%;">Qtd Alertas</th>
                    <th class="right" style="width:25%;">Pico Registrado</th>
                    <th class="right" style="width:20%;">Média do Dia</th>
                </tr>
            </thead>
            <tbody>
                {rows_dias}
            </tbody>
        </table>

        <!-- INFORMAÇÕES TÉCNICAS E RODAPÉ -->
        <div class="box-info">
            <strong>Critérios Operacionais da Torre de Controle:</strong><br>
            • Caminhões / Pesados: tolerância de excesso > 90 km/h | Veículos Leves / Médios / Vans: tolerância > 110 km/h.<br>
            • Filtro corporativo de saneamento ativo: leituras espúrias (> 160 km/h) expurgadas do banco.<br>
            • Contato / Tratativas da Torre de Controle: <strong>torredecontrole@gritsch.com.br</strong>
        </div>
    </body>
    </html>
    """

    html_file = os.path.join(OUTPUT_DIR, 'relatorio_telemetria_filial_GOI.html')
    pdf_file = os.path.join(OUTPUT_DIR, 'relatorio_telemetria_filial_GOI.pdf')
    
    with open(html_file, 'w', encoding='utf-8') as f:
        f.write(html)
    
    HTML(string=html).write_pdf(pdf_file)
    print(f"✅ Relatório Clean Sequencial da Filial GOI gerado com sucesso!")
    save_pdf_pages_as_png(pdf_file, 'preview_filial_GOI')

def gerar_pdf_consolidado_diretoria():
    conn = get_connection()
    cur = conn.cursor()

    # KPIs Globais
    cur.execute("""
        SELECT 
            COUNT(*) AS total_alertas,
            COUNT(DISTINCT filial_operacional) AS filiais_com_evento,
            COUNT(DISTINCT placa) AS qtd_veiculos,
            ROUND(AVG(velocidade_registrada)::numeric, 1) AS vel_media,
            MAX(velocidade_registrada) AS vel_max
        FROM torre.vw_alertas_telemetria_saneados
        WHERE data_hora_timestamp >= CURRENT_DATE - INTERVAL '14 days';
    """)
    tot_alertas, tot_filiais, tot_veiculos, vel_media_glob, vel_max_glob = cur.fetchone()

    # Ranking de Filiais (Top 15 para Página 1)
    cur.execute("""
        SELECT 
            s.filial_operacional,
            COUNT(*) AS total_alertas,
            COUNT(DISTINCT s.placa) AS qtd_veiculos,
            MAX(s.velocidade_registrada) AS vel_max,
            ROUND(AVG(s.velocidade_registrada)::numeric, 1) AS vel_media,
            COALESCE(ef.cc_regional, 'Diretoria') AS regional
        FROM torre.vw_alertas_telemetria_saneados s
        LEFT JOIN torre.email_gritsch_filiais ef ON ef.filial_operacional = s.filial_operacional
        WHERE s.data_hora_timestamp >= CURRENT_DATE - INTERVAL '14 days'
        GROUP BY s.filial_operacional, ef.cc_regional
        ORDER BY total_alertas DESC
        LIMIT 15;
    """)
    ranking_filiais = cur.fetchall()

    # Top Veículos Nacionais (Top 8 para Página 2)
    cur.execute("""
        SELECT 
            s.placa,
            s.filial_operacional,
            s.provedor_rastreador,
            s.modelo,
            s.grupo_veiculo,
            COUNT(*) AS qtd_alertas,
            MAX(s.velocidade_registrada) AS vel_pico,
            ROUND(AVG(s.velocidade_registrada)::numeric, 1) AS vel_media
        FROM torre.vw_alertas_telemetria_saneados s
        WHERE s.data_hora_timestamp >= CURRENT_DATE - INTERVAL '14 days'
        GROUP BY s.placa, s.filial_operacional, s.provedor_rastreador, s.modelo, s.grupo_veiculo
        ORDER BY qtd_alertas DESC
        LIMIT 8;
    """)
    top_veiculos = cur.fetchall()

    # Top 5 Ocorrências Críticas Nacionais
    cur.execute("""
        SELECT 
            s.placa,
            s.filial_operacional,
            s.provedor_rastreador,
            s.velocidade_registrada,
            s.data_hora_alerta,
            s.cidade,
            s.estado,
            s.modelo
        FROM torre.vw_alertas_telemetria_saneados s
        WHERE s.data_hora_timestamp >= CURRENT_DATE - INTERVAL '14 days'
        ORDER BY s.velocidade_registrada DESC, s.data_hora_timestamp DESC
        LIMIT 5;
    """)
    top_ocorrencias = cur.fetchall()

    # Anomalias Descartadas
    cur.execute("""
        SELECT 
            placa,
            filial_operacional,
            provedor_rastreador,
            velocidade_registrada,
            data_hora_alerta,
            motivo_descarte
        FROM torre.vw_telemetria_anomalias_descartadas
        WHERE velocidade_registrada > 160
        ORDER BY velocidade_registrada DESC
        LIMIT 3;
    """)
    anomalias_detalhe = cur.fetchall()

    cur.close()
    conn.close()

    rows_filiais = ""
    for f in ranking_filiais:
        pct = round((f[1] / tot_alertas) * 100, 1) if tot_alertas > 0 else 0
        rows_filiais += f"""
        <tr>
            <td class="text-bold text-primary">{f[0]}</td>
            <td class="text-muted">{f[5]}</td>
            <td class="center text-bold text-danger">{f[1]} <span class="text-muted">({pct}%)</span></td>
            <td class="center">{f[2]}</td>
            <td class="right text-danger">{f[3]:.0f} km/h</td>
            <td class="right text-muted">{f[4]} km/h</td>
        </tr>
        """

    rows_veiculos = ""
    for v in top_veiculos:
        rows_veiculos += f"""
        <tr>
            <td class="text-bold text-primary">{v[0]}</td>
            <td class="text-bold">{v[1]}</td>
            <td>{v[3] or '--'}</td>
            <td>{v[4] or 'Leve'}</td>
            <td class="center">{v[2]}</td>
            <td class="center text-bold text-danger">{v[5]}</td>
            <td class="right text-danger">{v[6]:.0f} km/h</td>
            <td class="right text-muted">{v[7]} km/h</td>
        </tr>
        """

    rows_top = ""
    for o in top_ocorrencias:
        rows_top += f"""
        <tr>
            <td class="text-bold text-primary">{o[0]}</td>
            <td class="text-bold">{o[1]}</td>
            <td>{o[7] or '--'}</td>
            <td class="center text-danger">{o[3]:.0f} km/h</td>
            <td class="center">{str(o[4])[:16]}</td>
            <td>{o[5] or ''}{('/' + o[6]) if o[6] else ''}</td>
            <td class="center">{o[2]}</td>
        </tr>
        """

    rows_anomalias = ""
    for a in anomalias_detalhe:
        rows_anomalias += f"""
        <tr>
            <td class="text-bold">{a[0]}</td>
            <td>{a[1]}</td>
            <td class="center">{a[2]}</td>
            <td class="center text-danger">{a[3]:.0f} km/h</td>
            <td class="center">{str(a[4])[:16]}</td>
            <td class="center text-bold" style="color:#991B1B;">{a[5]} (EXPURGADO)</td>
        </tr>
        """

    html_consolidado = f"""
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
        <meta charset="UTF-8">
        <title>Painel Consolidado de Telemetria — Diretoria</title>
        <style>{CSS_CLEAN_STACKED_STYLES}</style>
    </head>
    <body>
        <!-- =================== PÁGINA 1 =================== -->
        <!-- CABEÇALHO -->
        <table class="header-table">
            <tr>
                <td style="width:110px;">
                    <img src="file://{LOGO_PATH}" class="logo-img" alt="Gritsch" />
                </td>
                <td class="header-title">
                    <h1>PAINEL CONSOLIDADO DE TELEMETRIA & VELOCIDADE</h1>
                    <p>Visão Executiva Diretoria | Período: <strong>05/08/2026 a 19/08/2026</strong> | Emissão: <strong>{datetime.now().strftime('%d/%m/%Y %H:%M')}</strong></p>
                    <p>Torre de Controle | Destinatário: <strong>Diretoria Nacional</strong></p>
                </td>
            </tr>
        </table>

        <!-- 1. RESUMO EXECUTIVO (TABELA SEQUENCIAL 100%) -->
        <div class="section-header">1. Resumo Executivo Nacional</div>
        <table class="tbl-clean">
            <thead>
                <tr>
                    <th class="center" style="width:25%;">Total de Infrações</th>
                    <th class="center" style="width:25%;">Filiais com Ocorrência</th>
                    <th class="center" style="width:25%;">Veículos Ofensores</th>
                    <th class="center" style="width:25%;">Pico de Velocidade Real</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td class="center text-bold text-danger" style="font-size:8pt;">{tot_alertas} ocorrências</td>
                    <td class="center text-bold" style="font-size:8pt;">{tot_filiais} de 34 filiais</td>
                    <td class="center text-bold" style="font-size:8pt;">{tot_veiculos} veículos</td>
                    <td class="center text-bold text-danger" style="font-size:8pt;">{vel_max_glob:.0f} km/h (Média: {vel_media_glob} km/h)</td>
                </tr>
            </tbody>
        </table>

        <!-- 2. RANKING DE FILIAIS (TABELA SEQUENCIAL 100%) -->
        <div class="section-header">2. Ranking por Filial Operacional (Principais Unidades)</div>
        <table class="tbl-clean">
            <thead>
                <tr>
                    <th style="width:30%;">Filial Operacional</th>
                    <th style="width:26%;">Gestor Regional (CC)</th>
                    <th class="center" style="width:14%;">Infrações (%)</th>
                    <th class="center" style="width:10%;">Veículos</th>
                    <th class="right" style="width:10%;">Pico</th>
                    <th class="right" style="width:10%;">Média</th>
                </tr>
            </thead>
            <tbody>
                {rows_filiais}
            </tbody>
        </table>

        <!-- =================== PÁGINA 2 =================== -->
        <div class="page-break"></div>

        <table class="header-table">
            <tr>
                <td style="width:110px;">
                    <img src="file://{LOGO_PATH}" class="logo-img" alt="Gritsch" />
                </td>
                <td class="header-title">
                    <h1>DETALHAMENTO OPERACIONAL & AUDITORIA</h1>
                    <p>Visão Consolidada | Período: <strong>05/08/2026 a 19/08/2026</strong></p>
                </td>
            </tr>
        </table>

        <!-- 3. TOP VEÍCULOS DA FROTA NACIONAL (TABELA SEQUENCIAL 100%) -->
        <div class="section-header">3. Ranking Nacional de Veículos Mais Ofensores (Top Unidades)</div>
        <table class="tbl-clean">
            <thead>
                <tr>
                    <th style="width:12%;">Placa</th>
                    <th style="width:20%;">Filial</th>
                    <th style="width:26%;">Modelo</th>
                    <th style="width:12%;">Categoria</th>
                    <th class="center" style="width:10%;">Rastreador</th>
                    <th class="center" style="width:6%;">Qtd</th>
                    <th class="right" style="width:7%;">Pico</th>
                    <th class="right" style="width:7%;">Média</th>
                </tr>
            </thead>
            <tbody>
                {rows_veiculos}
            </tbody>
        </table>

        <!-- 4. TOP OCORRÊNCIAS CRÍTICAS (TABELA SEQUENCIAL 100%) -->
        <div class="section-header">4. Maiores Velocidades Registradas na Rede</div>
        <table class="tbl-clean">
            <thead>
                <tr>
                    <th style="width:12%;">Placa</th>
                    <th style="width:18%;">Filial</th>
                    <th style="width:24%;">Modelo</th>
                    <th class="center" style="width:11%;">Velocidade</th>
                    <th class="center" style="width:16%;">Data / Hora</th>
                    <th style="width:11%;">Local</th>
                    <th class="center" style="width:8%;">Origem</th>
                </tr>
            </thead>
            <tbody>
                {rows_top}
            </tbody>
        </table>

        <!-- 5. AUDITORIA DE ANOMALIAS DESCARTADAS (TABELA SEQUENCIAL 100%) -->
        <div class="section-header">5. Auditoria de Qualidade — Pontos Sombra Expurgados pelo DW</div>
        <table class="tbl-clean">
            <thead>
                <tr>
                    <th style="width:14%;">Placa</th>
                    <th style="width:22%;">Filial</th>
                    <th class="center" style="width:12%;">Provedor</th>
                    <th class="center" style="width:14%;">Velocidade Bruta</th>
                    <th class="center" style="width:18%;">Data / Hora</th>
                    <th class="center" style="width:20%;">Ação de Governança</th>
                </tr>
            </thead>
            <tbody>
                {rows_anomalias}
            </tbody>
        </table>

        <!-- RODAPÉ TÉCNICO -->
        <div class="box-info">
            <strong>Critérios de Governança e Qualidade de Dados:</strong><br>
            • Rastreabilidade de fontes: 3STEC, NUXEO e OMNILINK integrados via DW PostgreSQL.<br>
            • Regras de descarte: leituras espúrias (> 160 km/h) e inconsistências são expurgadas automaticamente.<br>
            • Contato / Suporte: <strong>torredecontrole@gritsch.com.br</strong>
        </div>
    </body>
    </html>
    """

    html_file = os.path.join(OUTPUT_DIR, 'relatorio_telemetria_consolidado_diretoria.html')
    pdf_file = os.path.join(OUTPUT_DIR, 'relatorio_telemetria_consolidado_diretoria.pdf')
    
    with open(html_file, 'w', encoding='utf-8') as f:
        f.write(html_consolidado)
    
    HTML(string=html_consolidado).write_pdf(pdf_file)
    print(f"✅ Relatório Clean Sequencial da Diretoria gerado com sucesso!")
    save_pdf_pages_as_png(pdf_file, 'preview_consolidado_diretoria')

if __name__ == '__main__':
    gerar_pdf_filial_goi()
    gerar_pdf_consolidado_diretoria()
