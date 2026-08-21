#!/usr/bin/env python3
"""
Script Gerador dos Templates HTML para E-mail n8n (Filial + Consolidado)
Estilo Tabelas Limpas Sequenciais (Padrão Corporativo Gritsch)
"""

def gerar_html_email_filial():
    return """
    var d = $json;
    var fmtNum = function(n) { return String(n).replace(/(\\d)(?=(\\d{3})+(?!\\d))/g, '$1.'); };
    var BORDA = '#D1D5DB';
    var FUNDO = '#F9FAFB';
    var AZUL_ESC = '#1E3A5F';
    
    var rowsVeiculos = '';
    var veiculos = d.tabelaPlacas || [];
    for (var i = 0; i < veiculos.length; i++) {
        var v = veiculos[i];
        var bg = i % 2 === 0 ? '#FFFFFF' : '#F9FAFB';
        rowsVeiculos += '<tr style=\"background:' + bg + '\">'
            + '<td style=\"padding:4px 6px;border:1px solid #E5E7EB;font-weight:bold;color:' + AZUL_ESC + '\">' + v.placa + '</td>'
            + '<td style=\"padding:4px 6px;border:1px solid #E5E7EB;\">' + (v.modelo || '--') + '</td>'
            + '<td style=\"padding:4px 6px;border:1px solid #E5E7EB;\">' + (v.grupo_veiculo || 'Leve') + '</td>'
            + '<td style=\"padding:4px 6px;border:1px solid #E5E7EB;text-align:center;\">' + (v.provedor || 'NUXEO') + '</td>'
            + '<td style=\"padding:4px 6px;border:1px solid #E5E7EB;text-align:center;font-weight:bold;\">' + v.qtd + '</td>'
            + '<td style=\"padding:4px 6px;border:1px solid #E5E7EB;text-align:right;font-weight:bold;color:#991B1B;\">' + Math.round(v.velMax) + ' km/h</td>'
            + '<td style=\"padding:4px 6px;border:1px solid #E5E7EB;text-align:right;color:#6B7280;\">' + (v.velMedia || '--') + ' km/h</td>'
            + '</tr>';
    }

    var rowsTop = '';
    var topOc = d.topOcorrencias || [];
    for (var i = 0; i < topOc.length; i++) {
        var o = topOc[i];
        var bg = i % 2 === 0 ? '#FFFFFF' : '#F9FAFB';
        rowsTop += '<tr style=\"background:' + bg + '\">'
            + '<td style=\"padding:4px 6px;border:1px solid #E5E7EB;font-weight:bold;color:' + AZUL_ESC + '\">' + o.placa + '</td>'
            + '<td style=\"padding:4px 6px;border:1px solid #E5E7EB;\">' + (o.modelo || '--') + '</td>'
            + '<td style=\"padding:4px 6px;border:1px solid #E5E7EB;text-align:center;font-weight:bold;color:#991B1B;\">' + Math.round(o.velocidade) + ' km/h</td>'
            + '<td style=\"padding:4px 6px;border:1px solid #E5E7EB;text-align:center;\">' + String(o.data).substring(0, 16) + '</td>'
            + '<td style=\"padding:4px 6px;border:1px solid #E5E7EB;\">' + (o.local || '--') + '</td>'
            + '<td style=\"padding:4px 6px;border:1px solid #E5E7EB;text-align:center;\">' + (o.origem || 'NUXEO') + '</td>'
            + '</tr>';
    }

    var rowsDias = '';
    var bd = d.breakdownDias || [];
    for (var i = 0; i < bd.length; i++) {
        var b = bd[i];
        var bg = i % 2 === 0 ? '#FFFFFF' : '#F9FAFB';
        rowsDias += '<tr style=\"background:' + bg + '\">'
            + '<td style=\"padding:4px 6px;border:1px solid #E5E7EB;text-align:center;font-weight:bold;\">' + b.dia + '</td>'
            + '<td style=\"padding:4px 6px;border:1px solid #E5E7EB;text-align:center;font-weight:bold;\">' + b.qtd + '</td>'
            + '<td style=\"padding:4px 6px;border:1px solid #E5E7EB;text-align:right;font-weight:bold;color:#991B1B;\">' + Math.round(b.velPico || 0) + ' km/h</td>'
            + '</tr>';
    }

    var html = '<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head>'
        + '<body style=\"margin:0;padding:20px;background:#F3F4F6;font-family:Arial,sans-serif;color:#1F2937;font-size:12px;line-height:1.4;\">'
        + '<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" style=\"max-width:760px;margin:0 auto;background:#FFFFFF;border:1px solid ' + BORDA + ';border-radius:4px;overflow:hidden;\">'
        + '<tr><td style=\"padding:16px 20px;border-bottom:2px solid ' + AZUL_ESC + ';\">'
        + '<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr>'
        + '<td style=\"vertical-align:middle;width:120px;\"><img src=\"https://gritsch.com.br/wp-content/uploads/2022/03/logomarca-1_gritsch-1.png\" width=\"100\" style=\"display:block;\" alt=\"Gritsch\"></td>'
        + '<td style=\"text-align:right;vertical-align:middle;\">'
        + '<div style=\"font-size:15px;font-weight:bold;color:' + AZUL_ESC + ';\">RELATÓRIO DE TELEMETRIA & VELOCIDADE</div>'
        + '<div style=\"font-size:11px;color:#4B5563;margin-top:2px;\">Unidade: <strong>' + d.filial + '</strong> | Período: <strong>' + d.dataRef + '</strong></div>'
        + '<div style=\"font-size:10px;color:#9CA3AF;margin-top:2px;\">Destinatário: ' + d.emailDestino + ' | Regional: ' + (d.emailCC || '--') + '</div>'
        + '</td></tr></table></td></tr>'
        
        + '<tr><td style=\"padding:16px 20px;\">'
        
        // 1. Resumo da Unidade
        + '<div style=\"font-size:11px;font-weight:bold;color:' + AZUL_ESC + ';text-transform:uppercase;border-bottom:1px solid ' + AZUL_ESC + ';padding-bottom:3px;margin-bottom:6px;\">1. Resumo Consolidado da Unidade</div>'
        + '<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" style=\"border-collapse:collapse;border:1px solid ' + BORDA + ';margin-bottom:14px;font-size:11px;\">'
        + '<thead><tr style=\"background:#F3F4F6;\">'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:center;\">TOTAL DE INFRAÇÕES</th>'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:center;\">VEÍCULOS COM APONTAMENTO</th>'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:center;\">VELOCIDADE MÁXIMA</th>'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:center;\">MÉDIA DOS EXCESSOS</th>'
        + '</tr></thead>'
        + '<tbody><tr>'
        + '<td style=\"padding:6px;border:1px solid ' + BORDA + ';text-align:center;font-weight:bold;color:#991B1B;font-size:13px;\">' + d.totalEventos + ' ocorrências</td>'
        + '<td style=\"padding:6px;border:1px solid ' + BORDA + ';text-align:center;font-weight:bold;font-size:13px;\">' + (d.qtdVeiculos || (d.tabelaPlacas||[]).length) + ' veículos</td>'
        + '<td style=\"padding:6px;border:1px solid ' + BORDA + ';text-align:center;font-weight:bold;color:#991B1B;font-size:13px;\">' + Math.round(d.velMax) + ' km/h</td>'
        + '<td style=\"padding:6px;border:1px solid ' + BORDA + ';text-align:center;font-weight:bold;font-size:13px;\">' + d.velMedia + ' km/h</td>'
        + '</tr></tbody></table>'

        // 2. Veículos com Excesso
        + '<div style=\"font-size:11px;font-weight:bold;color:' + AZUL_ESC + ';text-transform:uppercase;border-bottom:1px solid ' + AZUL_ESC + ';padding-bottom:3px;margin-bottom:6px;\">2. Veículos com Excesso de Velocidade no Período</div>'
        + '<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" style=\"border-collapse:collapse;border:1px solid ' + BORDA + ';margin-bottom:14px;font-size:11px;\">'
        + '<thead><tr style=\"background:#F3F4F6;\">'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:left;\">PLACA</th>'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:left;\">MODELO</th>'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:left;\">CATEGORIA</th>'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:center;\">RASTREADOR</th>'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:center;\">ALERTAS</th>'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:right;\">PICO</th>'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:right;\">MÉDIA</th>'
        + '</tr></thead>'
        + '<tbody>' + rowsVeiculos + '</tbody></table>'

        // 3. Top Ocorrências
        + '<div style=\"font-size:11px;font-weight:bold;color:' + AZUL_ESC + ';text-transform:uppercase;border-bottom:1px solid ' + AZUL_ESC + ';padding-bottom:3px;margin-bottom:6px;\">3. Ocorrências com Maiores Velocidades Registradas</div>'
        + '<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" style=\"border-collapse:collapse;border:1px solid ' + BORDA + ';margin-bottom:14px;font-size:11px;\">'
        + '<thead><tr style=\"background:#F3F4F6;\">'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:left;\">PLACA</th>'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:left;\">MODELO</th>'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:center;\">VELOCIDADE</th>'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:center;\">DATA / HORA</th>'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:left;\">LOCAL</th>'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:center;\">ORIGEM</th>'
        + '</tr></thead>'
        + '<tbody>' + rowsTop + '</tbody></table>'

        // 4. Volume Diário
        + '<div style=\"font-size:11px;font-weight:bold;color:' + AZUL_ESC + ';text-transform:uppercase;border-bottom:1px solid ' + AZUL_ESC + ';padding-bottom:3px;margin-bottom:6px;\">4. Evolução do Volume por Data</div>'
        + '<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" style=\"border-collapse:collapse;border:1px solid ' + BORDA + ';margin-bottom:14px;font-size:11px;\">'
        + '<thead><tr style=\"background:#F3F4F6;\">'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:center;\">DATA</th>'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:center;\">QTD ALERTAS</th>'
        + '<th style=\"padding:5px;border:1px solid ' + BORDA + ';text-align:right;\">PICO REGISTRADO</th>'
        + '</tr></thead>'
        + '<tbody>' + rowsDias + '</tbody></table>'

        // Rodapé
        + '<div style=\"border:1px solid ' + BORDA + ';background:#F9FAFB;padding:8px 10px;font-size:10px;color:#4B5563;border-left:3px solid ' + AZUL_ESC + ';\">'
        + '<strong>Critérios Operacionais da Torre de Controle:</strong><br>'
        + '• Caminhões / Pesados: tolerância de excesso > 90 km/h | Leves / Vans: tolerância > 110 km/h.<br>'
        + '• Filtro corporativo ativo: leituras espúrias (> 160 km/h) expurgadas do banco.<br>'
        + '• Dúvidas e tratativas: <strong>torredecontrole@gritsch.com.br</strong>'
        + '</div>'

        + '</td></tr></table></body></html>';

    return [{ json: Object.assign({}, d, { htmlEmail: html }) }];
    """

print("Gerador configurado.")
