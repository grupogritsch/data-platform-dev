// Calcular Período Diário -- mesma regra do telemetria (02 - Calcular
// Periodo): roda de segunda a sexta, cobrindo "ontem" -- exceto segunda,
// que cobre sexta+sabado+domingo (o intervalo desde o ultimo dia util).
// Formato de data em start_date/end_date segue o mesmo do node semanal
// (Calcular Período): 'YYYY-MM-DD', porque a coluna c.data no Postgres e'
// DATE e o SQL faz "data BETWEEN 'YYYY-MM-DD' AND 'YYYY-MM-DD'".
const cfg = $('⚙️ Configurações Diário').first().json;

const fmtPG = (d) => d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
const fmtLabel = (d) => String(d.getDate()).padStart(2, '0') + '/' + String(d.getMonth() + 1).padStart(2, '0') + '/' + d.getFullYear();

const agora = new Date();
const dow = agora.getDay(); // 0=Dom ... 6=Sab

// Segunda (dow=1) cobre desde sexta (recuo de 3 dias); demais dias uteis
// cobrem so o dia anterior.
const recuoInicio = dow === 1 ? 3 : 1;

const fim = new Date(agora);
fim.setDate(agora.getDate() - 1);

const inicio = new Date(agora);
inicio.setDate(agora.getDate() - recuoInicio);

// Comparacao: o(s) dia(s) uteis imediatamente anteriores ao periodo atual,
// mesma quantidade de dias (janela deslizante), pra nao comparar 1 dia
// contra 3 (segunda) de forma injusta.
const qtdDias = Math.round((fim - inicio) / 86400000) + 1;
const fimAnt = new Date(inicio);
fimAnt.setDate(inicio.getDate() - 1);
const inicioAnt = new Date(fimAnt);
inicioAnt.setDate(fimAnt.getDate() - (qtdDias - 1));

const start_date = fmtPG(inicio);
const end_date = fmtPG(fim);
const start_date_ant = fmtPG(inicioAnt);
const end_date_ant = fmtPG(fimAnt);

const dataRef = start_date === end_date ? fmtLabel(inicio) : fmtLabel(inicio) + ' a ' + fmtLabel(fim);

return [{
  json: {
    start_date,
    end_date,
    start_date_ant,
    end_date_ant,
    dataRef,
    modo_producao: cfg.modo_producao,
    email_teste: cfg.email_teste,
  },
}];
