/**
 * Apps Script preso na Planilha Google de fechamento (Extensões > Apps
 * Script, colar este arquivo inteiro). Roda por gatilho semanal, DEPOIS do
 * n8n ter escrito os dados da semana (deixar pelo menos 1-2h de folga --
 * n8n roda quinta 06h, este script quinta 08h por padrão).
 *
 * O que faz: le a ultima linha da aba "Info" (escrita pelo n8n com
 * data_vencimento + timestamp), confere se foi atualizada HOJE (senao,
 * quer dizer que o n8n nao achou fatura pendente essa semana -- nao manda
 * nada, sai em silencio), exporta a planilha inteira como .xlsx de verdade
 * (mesmo motor do "Baixar como Excel" do proprio Sheets -- reproduz as 5
 * abas certinho, sem a gambiarra de biblioteca externa que o node Code do
 * n8n precisava) e manda por e-mail pro destinatario unico.
 *
 * Configuracao antes de usar (ver truckpag-fechamento-fatura/docs/
 * automacao-fechamento-sheets.md pro passo a passo completo):
 *   1. Trocar DESTINATARIO abaixo.
 *   2. Rodar configurarGatilhoSemanal() uma vez (Executar > selecionar essa
 *      funcao) pra criar o gatilho de quinta-feira. So precisa rodar 1 vez;
 *      ele fica salvo mesmo depois de fechar o editor.
 */

const DESTINATARIO = 'PREENCHER-destinatario@empresa.com.br';
const ABA_INFO = 'Info';
const FUSO = 'America/Sao_Paulo';

function enviarFechamentoSemanal() {
  const ss = SpreadsheetApp.getActive();
  const abaInfo = ss.getSheetByName(ABA_INFO);
  if (!abaInfo || abaInfo.getLastRow() < 2) {
    Logger.log('Aba Info vazia ou nao existe -- nada pra enviar ainda.');
    return;
  }

  const ultimaLinha = abaInfo.getRange(abaInfo.getLastRow(), 1, 1, 2).getValues()[0];
  const dataVencimento = ultimaLinha[0];
  const atualizadoEm = new Date(ultimaLinha[1]);

  const hojeStr = Utilities.formatDate(new Date(), FUSO, 'yyyy-MM-dd');
  const atualizadoStr = Utilities.formatDate(atualizadoEm, FUSO, 'yyyy-MM-dd');

  if (hojeStr !== atualizadoStr) {
    Logger.log(
      'Info nao foi atualizada hoje (ultima atualizacao: ' + atualizadoStr + '). ' +
      'O n8n provavelmente nao achou fatura pendente essa semana -- nao envia e-mail.'
    );
    return;
  }

  const arquivo = DriveApp.getFileById(ss.getId());
  const blobXlsx = arquivo.getAs(MimeType.MICROSOFT_EXCEL);
  blobXlsx.setName('Fechamento_Fatura_Combustivel_' + dataVencimento + '.xlsx');

  MailApp.sendEmail({
    to: DESTINATARIO,
    subject: 'Fechamento fatura combustível Truckpag - vencimento ' + dataVencimento,
    body:
      'Segue em anexo o pacote de conciliação da fatura de combustível Truckpag ' +
      '(Resumo, Contabilidade, Relatorio, Rateio por Garagem e Rateio por Posto).\n\n' +
      'Gerado automaticamente.',
    attachments: [blobXlsx],
  });

  Logger.log('E-mail enviado para ' + DESTINATARIO + ' (vencimento ' + dataVencimento + ').');
}

/**
 * Roda isto UMA VEZ (Executar > configurarGatilhoSemanal, no editor do
 * Apps Script) pra criar o gatilho semanal. Remove qualquer gatilho antigo
 * da mesma funcao antes, pra nao duplicar se rodar de novo por engano.
 */
function configurarGatilhoSemanal() {
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === 'enviarFechamentoSemanal') {
      ScriptApp.deleteTrigger(t);
    }
  });

  ScriptApp.newTrigger('enviarFechamentoSemanal')
    .timeBased()
    .onWeekDay(ScriptApp.WeekDay.THURSDAY)
    .atHour(8)
    .create();

  Logger.log('Gatilho semanal criado: toda quinta-feira, por volta das 8h.');
}

/**
 * Util pra testar sem esperar quinta-feira: roda enviarFechamentoSemanal()
 * na hora, ignorando a checagem de "atualizado hoje". Usar com cuidado --
 * manda e-mail de verdade pro DESTINATARIO configurado acima.
 */
function testarEnvioAgora() {
  const ss = SpreadsheetApp.getActive();
  const abaInfo = ss.getSheetByName(ABA_INFO);
  if (!abaInfo || abaInfo.getLastRow() < 2) {
    Logger.log('Aba Info vazia -- rode o workflow n8n primeiro pra ter dado pra testar.');
    return;
  }
  const ultimaLinha = abaInfo.getRange(abaInfo.getLastRow(), 1, 1, 2).getValues()[0];
  const dataVencimento = ultimaLinha[0];

  const arquivo = DriveApp.getFileById(ss.getId());
  const blobXlsx = arquivo.getAs(MimeType.MICROSOFT_EXCEL);
  blobXlsx.setName('TESTE_Fechamento_Fatura_Combustivel_' + dataVencimento + '.xlsx');

  MailApp.sendEmail({
    to: DESTINATARIO,
    subject: '[TESTE] Fechamento fatura combustível Truckpag - vencimento ' + dataVencimento,
    body: 'Envio de teste manual (testarEnvioAgora) -- ignorando a checagem de data.',
    attachments: [blobXlsx],
  });

  Logger.log('E-mail de TESTE enviado para ' + DESTINATARIO);
}
