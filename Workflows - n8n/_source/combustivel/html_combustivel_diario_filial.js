// ===========================================================================
// Gerar HTML — Combustível DIÁRIO por Filial
// Mesma identidade visual do semanal (header TruckPag + faixa topografica,
// rodape Gritsch padrao Torre de Controle), mas enxuto: so a tabela de KPIs
// (pedido do usuario 24/08/2026 -- "diario mais enxuto e semanal com dados
// em anexo pra gestores"). Sem Top 5, sem Postos, sem Custo por grupo de
// veiculo, sem CSV em anexo -- so o pulso do dia. runOnceForEachItem.
//
// Mesma logica de calculo de periodo do telemetria diario (02 - Calcular
// Periodo): roda seg-sex, segunda cobre sexta+fim de semana.
// ===========================================================================

const d = $input.item.json;
const cfgNode = $('⚙️ Configurações Diário').first().json;
const perNode = $('Calcular Período Diário').first().json;

const cfg = {
  modo_producao: cfgNode.modo_producao || false,
  email_teste: cfgNode.email_teste || 'gabriel.brittes@gritsch.com.br',
};
const per = { dataRef: perNode.dataRef || 'Hoje' };

const emailFinal = cfg.modo_producao ? (d.email_gestor || cfg.email_teste) : cfg.email_teste;

// CC: mesma logica do semanal/telemetria -- funde email_cc + cc_regional +
// cc_global, deduplica e separa por virgula.
const ccParts = [];
if (d.email_cc) ccParts.push(d.email_cc);
if (d.cc_regional) ccParts.push(d.cc_regional);
if (d.cc_global) ccParts.push(d.cc_global);
const ccMerged = ccParts.join(';').split(/[;,]+/).map(s => s.trim()).filter(Boolean)
  .filter((v, i, a) => a.indexOf(v) === i).join(',');
const ccFinal = cfg.modo_producao ? ccMerged : '';

// --- Paleta TruckPag (identica ao semanal) ---------------------------------
const VERDE       = '#00B140';
const VERDE_ESC   = '#067A34';
const GRAFITE     = '#1D2321';
const CINZA       = '#5B645F';
const LINHA       = '#DCE3DE';
const FUNDO       = '#F4F7F5';
const BRANCO      = '#FFFFFF';
const ALERTA      = '#C23B33';

const F_DISPLAY = "'Manrope','Segoe UI',Arial,sans-serif";
const F_CORPO   = "'IBM Plex Sans','Segoe UI',Arial,sans-serif";

// Logo TruckPag: anexo inline (CID), mesma solucao do semanal -- ver
// comentario detalhado em html_combustivel_semanal_filial.js.
const TRUCKPAG_LOGO_B64 = 'iVBORw0KGgoAAAANSUhEUgAAAbIAAABUCAYAAADnGbI3AABZUElEQVR42u29eZxc11Un/j3n3ldVvWm1NltbL95kbXY7XqRWSsoCzgRCcNICAiQDTDZ2hh1maDXDABP4sQWSsIUQMkBUIRmy4ZBJpLJbshNLttb2pm5JlixZkq2tt6p6757z++O9qq7eu163FiZ1/OmPLKlV/d59992zfc/3Sxht2sGgTin+tqnnLXOh/gr0FxYTTAKGFE4JN7E5Q8LWXfSBM6fu3ntm+N7aDSjjbtiFKQgEXfXkg6vtfO8u5EiBSdYyWmtNwU8FF5/oXttdKH4Gqla1yvcfgyBNBzb/T641P695SUFAINA0/q1SgklFnqPAfNex9dlXAKC6F6t2M5gd8bud7QbU6QCg5Ujbu2HpXTqUexiKW2GNB4r2O9/UfgxGAfgsCcLlpqNtB4n1K75Pn3yZMpciR63AdX4Bd7YbICMt3ZsfgjH/CtHFaoHSmk52PwmLfG7+P6EDP4IdHQA6q4dH1SqzjtCJrT646U5i+g34CkgUFk3HCKQF58yCxN3Ba/5bQfi79K60zSIbVBe3ajfaSps4vStts9uyQeOzDz3ASe8PucZsIQCSE2gg+A8XdxFATKAUgzyGDLpTEkhH79quv0MHGDug1zWaHI6GH7cLEluCS4WAiOw0/p1QklkK7hVONTQfu+OxfDUrq1rl+y+sRjQd2vz9ptZ+XgYCByJT2WeoUK0llwu+7/i6PV+64RWOqlUtMi5u8tCJbfphrvUe5yRvcVd9F1z1nRZEof8BD00FNFCVgcAFlwoBFCtMg/1k8+G2v0QnBOggKOh6OrHGA213kEcPuiu+EKZ5iJAqWQIBJ6pOrGpxLb37PEV7cRUsQePsISLWnAM5OR7+wZrqPqzaTeLIdoZRVePBh99t6uxn4CPp+gNHRIaITFR6IPzHzDcJIENEVgsi7oofmPneB5oPbv44qFOQaefrc4ikOTwH5Pu4ziZUVaZd0gEUhgDQyfC31+eaq/b/bJ/s9pj/TskQ4HCZa8258A+rJe6q3SyOrD0jjQfa7mDP/j0CVTgRqrTk8B/DqTGBbHDJ93l+4kPNz7Z9ANszLuxdXVvLbs26MPujd2kQ/s/0qzkAha6rd0RkXbWqVbQHt0oYTNFqiIIqrUYQFB5BCeeO3f7m16tAj6rdXI4srDJ8xNSaWvXFgej/6YifBFYHAlGL32869vBibM+4a1pi1A4GQZsPbF5Dllp10Ckw/UCBAFIHaOTIqla1eLWJTgkBH7pSA0XlVRYNMzLSk6XPqlrVbhZHtvpA24Pk0fe4vkAwHfDB/wOvtBREzBw7Xwf5J6LS3zXLytK7d3OE9Hwn11ur0Mqa40qsvoAjR5a9sLgaBVet4n4xAKx8V9tcKG5FoNODy45qOcMQSOkEAKS3pquOrGo3jyMzpO/jlDFQ/Y45IIlAWhAl0HbsbDfZrdlrhbyi7NasQwdYVR/VglRUVoRCYUCSF1/ZhHM77ZmqI6tahdZBAGDF3QaieRpo7K63QqqVgardfI5MCWn1K4/Q/mNHqMSaE4Jizarbz68AQa9JqUQ7CARd/e7N68jjjTokFZUVAYAsgVRfs8Y/NzK+rlrVpmvdFBYjzHKuNYywKlDR+04KgiigdCzsuVUrA1W7iRwZKZrUl2Eo/ndIxwAC5RQnDLtmAMCOdrpWZUUj9C6uN1xxWRGqMAQFXn3h7r19N2WDPZzGG/6q2szW7xqsZwkgRNocImDj7CFiGRKoyCkAQKa63jfVdd/s7941vnYLotR3ZoyvQh4byruFxZc9O1vgjkwYAWe3QqFgPYy3wq8MrVjKHT0GhtxJ7Gw3aOpl9DbJiO9oz8i0nVsHGDvaqaJDqH2NllOWDWPY2hkZYMxArHZwevduzm7NukmvqwOMe2IGD9unNYRL2BlzVKGSNY0xU5jeneYwo5nmz9nZbtAe7dGtixU7MhrOQla6mdAMDr0YVQq9t0QSSL9L2dOlNZpsbjIT89nOdO01GhfKtBMWnad0MXvMTPOzo3ckXOusgCpf55ldewdh924ecd3bM25aa1J69yrYW9foHopBfPbCYp3WuisImXYu7vPhrH+NAp1TkldQ86G279ASgQbc4Fk3ELynd23XPxWZTa7Fg20+tPkMJXipFlQrmB+DQgMzz7PuUuH3ejfs/Y2pOBynw/M4E47I8bg4Vx1Pp8yVwhwWowMyNHD2/v2D03KondfxgJjpPc/CZ6V3p814zn39gbfWFRKXU/mArbMJpj5Wz3OOxahNIde9Nts/xWdOfdhGz6zp4OYvmAb7TumrkNWjyC6Tl575/tDd++/f74+7PsXDaPt1YvuIfl56UfHgy0554Lfua/WGUvVJ4cHk4GAqgVrAFgJXsBqYC8nBk9uyubEHcztfM8dQDGwuLNbJ1q3lxUeSfYPO1gUXbSHlmURANgissTZwThOFkxsX940OKtu13WSul0MrBskTML2sObImUeivT9k56uUDtkmb4PyVgtQ0pAa6LyCHqc7e6DmEAcZWGU0zWHVks+PIqLiozQe33Ocs6uF8YrIBBCtB+HtieHCoyJEB6rjWGhkI/gzMnwUkIRyVJwPA1lvoFXn+2H1dFyY9eKO/u+2pB5YnFtXcRX1BTkiYLE387APAELMDLh1f33Vo1CFFjYc3PcqGf4gUGyTAEiIISC8R43kB/VvhSvDXpzc9NTTmuqLfr+jadGtqkWkJck4xHaxsAKg1RIrc8bVPfHtCZ1P2Z7cfbXvQByUpmP7PsClDwcXCC8cf/ta5GTuz4iFY9nKvPrjpTrLURkpvZOB2dbgNhAaFJggwUBIFAiIVBfoBukDAqwCdAPQYWTpCxj/60p1PvTIyY5vkwIp2Z9Ohtme5xmzUwUAqGrNRdVxvjet3u3s3dG2bat0bu9vuUENLabrPFoAGSpw0bn7/0LcndJRljrkd3ZQZ59Bctq+1ti6ZXCZEy9TX1Uy0AkSrlLAMwC1QLABpPYHqoFoTXboP0gKULhNwFpa6Cfi274I9J9c/+fyIdZ4tJ63tZnRm3fLiI0kU+psFuhHgZhJpgtJtSroQSnMBTQDwAHgg8gjwFPAJyCnpa6R0Bob2k2jXQH7om6Wg8lpSiY3e47vStnmh26BK62CkhRzdDcIKQOeqooGIUqrqEcGqIgDhMhR9IFxS1VcJfAmk55joFefwMhgvmwBnj93XdWFMyXxX2haDl+vjyBQajvZCy6lxaAL0QliCI8I17dvNoiMrRryHNn/M1NsPa15GYGe0MMPkwxCIRxUmFSCPIIPuZN4Fm09vfOoMdoDGZDrawUCnNh966F4kvH9jjxerL9PD9qiCEgzXF/x678Y9vw8Ajc88/AZO2T/iFLeF96ZQFxW5DYEsgesNgnP5r/S8cOv3lR+w7TvbTaY9I02Ht/wnStKnCVgAqaDOpQpKMVxf8De96/e8f0xmF13Gsv2tNbU2+Tmu996mfgUIPQXIAlLQMy5wbzqxfu+LQAeNU1rFtMqB0aHX8kzbIk3odhhuh+jDXGsTAACn0EDDX8tehNKjYQJsRGYWEXVrQSB5uUoGBwj8VZXCv/SsferYVJll0763zCVv6AVK8JJYlYE5npWr/qd61u/5MexK2xERdLHHsTttmhfJ/weLDxEoUdF6iYJqDdxV/197/2XPoxNyoZav64uPJJ0ObKBAW+HkHgKvB2GlKm7lJHtkw/2oGn4+BFAX/gpVqJQdOBSuMdlwzQFABoICEbqg+LtjXUOfxQf3+7PqzAA0H3moBca+DYK0OtxLQBPXG5Ch8PpUARddd5EhIcpFVKPrpuF3D5aAgkIK0gPGZwqD7q9Ote49UzwHZjU7K3OQKw+1NVlLP06qj5LibqqzoCKsyClUNHwGJU8wzIcLBshQuMcpJIBQBdQXaEEBp69DcVwNDpLBt12g3zqxds/hUiViZ7u5VnNjAlVVgpKSIY8IloksIWo2lx5GyaNF57QqgCB8wbUggKqLPodBNyEgRcGgTll5YEsjQT8sgw5wkBHyLDTDZqZTjYZYR3SptKCglFnlDXq3gfBK2BPKjAGcZLch0EPmJ+wcuzh4rVAgkDetfj+pQGHI499avvehP03W8Xdxnf0sQEnpC1x06hIUYWrnVDWvInlHCtpy562v1L5A6CseppkiWOWQ/LSpTSxwFwt+6DqmDZ1zMGSgeHP0mVKeDRczxtTRZCvXem+Tq4FUPC9VUGfmebfiSnA3CC9AuznuC76wa1PD/AX8X5XxQU55yxAoZMjBXfXdsMOiMc1uLePZRCGKAqMDiJSYDM3hBL+RLL1RBuyO5ufa/jcC6uxZ98SpcTKZ8LWyuSXEWDhmH1U2t3IMANIAsmNKb2u0ceE3PmvmeY+61/2im6jAWSIwTj0SNIa904yOm5Vtz7jGQ23rjYf3I+h/xIBaqNaGPyk6N+ALNCeqUBlet+gtVIp+HW/NVbWgoatQEDElqMa8CYw3NW+p/SU9tOU3e9dnvgLV6MSt0CkUfyYBTYfbfgBM74PIVq6xKYiGQWFBIH1BeOaV9/xKB+QEe8VXVQqvnRRMSW7mGtORBD7cfHDTf+uhzr+exZJ52H+mjFuxf9OtXsr8GkF/nGtNneYFmhfoVT86t8vWfZz9oKThBi/9Wr79wzOfLC0kjxfCo/uh+An0B9r8XNsR6uZ/KQwO/NXL92fO2tnMupTUkYIpYZhSDBCgOYEU5CIF8oqATpDijAKXQHoFoEESUWWuJdVaBdUR6UJVNILQREQruN4aMKG0QNCAFDxrDCQzja0y7QRkYC0ayWPVnNNrwI4y1hUqAMMkOdefdHxqogZ8SE2UBRQrNSdKgJm+YyWjvgglTU2i3vwzFG9Uh6TkgpHM/TQymSaPGc6dfOHMbYMj7mF7xoVjDrpMBp2iomsJX0IyRABeKI1MlGVk6UUhYIeFGgGIEoQAW9ncLxnXHzgD0xuDGLf0gq8+sOW7TQp/yjXmThlwcFf9oBhvjqGAo8meO438FgoDBhkMQjA8KGXmej8RXPTTa3al7+1GdmDEYRXtTyKsoKSxmhOpOCBUUJjB6PFxeERNdlsmaDq4+WN2QeLR4HW/QIBX0c8QFU6xJ3k5D+feFbHtcFnvr5jTc/PBM7+LBP8Cp9iTnEDzouL7EjIURbmVFjXWyNDoNaZJ15xKr1roNFQGA4ECVGM2UIK+3Hyk7U97iH6+hLarxClEgVbjoU1/bBcmfl4HHCSncFd8R8WgMHzmY697Onul7Nq1oBLkfWGPF/O8xF81H2l7cN6eoQ/vpynKttN2xhnXdKTth5jpj6nOLJGrQbjHiwlH8R5oOnscI3z16HtVX1X9QJUgoWMkQ4bXcY1Z51HNB5sObP7pmTsyDRNg8thwrbXqCyQvp6hPnlbVJ2CwD7XyYk/Lk+cr+dglB9bX1SXnNclAcC8IDwK0jQzdzXXWqq/QQacKFQLxjDOeGVjx8ITDSqpj0pyT6zYNZ4lUcGFoIV+aeJt0RpExNapTqnhekIg1L8q19h2aF+iQKPFkWZQqWYaSnA4PpAgcEkVmq96ZngMNlofirFQp6k6jss/xIrtEtjMr43zj7VEwIZUyYJBHpL70BSqvohJi3CLijDpd06HNv8YJ/B6YEFz2A4qIq2edDDvqo0pfAALswGoEoDCbGL0/CdJEnoXkXPjOVPbjWIcExHyinF0mrWmbpWzQfGDzr/Nc78PBZd8nQqUlxZDDEchrQd7V2/rUsVFODOldaZOlbNB88JUfs0tSvxJcKEiQdwFRFLFj2oFBHDEoAwJ0yAkIyvMTP9d0aPPSXuz5oVBBo3P6mVkUaDL4LToQiAy6INxx14TblomI1VeVK76z8xM/cXkzlq46nn73yR1bCxVd92gnBlDz4baPca35kOYErnyPX4uTONzvRCGlYnjI5ESDvDhO8TKwfCb+yxU6MHCtZRhABt1ZHXJfAvD5FMye7vXjoK0ieOiEn7kVyCKEjp6jQwMADkdfn27d1+pdTCY28oC+FYrvpyTfz0k20h9ARR2FB1flyzhLW4hUm0HhYXtdvGok74I8Xj3ZmM1N1oBfc+Sh+TnRJYjFsReJKg4FDkpc2kqTORsGIHqyVNpEJJuDTrUIbgNhXqnmH4NuiQg9U+zNltjxpiFCQOd61z/52rQPxRIQptM1HW77qJnj/bRc9QUioGtM+6aAcq0xeiX493AfTNTY56ZYhfkiu4wvefgIofdHM4pdoRNrfPahH+YG+7vS7wckFR5kCoUlRwljdcB/X+/GvV3Ylbagkb3q4vC1gtKSd04BISIP15cOiKGAXPR9uyDxA00HN1/t3dj5AWi7AabZM9tRzPP0CkInbK65sgiBCGSDi75vF3hv14uFz6Cz8924p4LrHlVCbj76zf9t5tsfdBcLAZSYrj+1IUW1Cta8qKoO2TgcNVAF19vwwfryLc3jE7mB/JfOPPj06yhryqYXnacRcwTUKdnpRsll8wjZrYt1P2V8AE9HX7/b0t2WlkH9IAiPmrleUq4GgGrlYoGzlh7p6uvOnxfG5C8Py7uM3pih88iTWUZECzTQGYwehpHptDGchGPjsUsERCu8WjY64KTSEiwBBKcAqGc8doki1ZgSrUYQY24vCg4kpyfDkfmRmcEkoTZje8Y1Hdr8V3ae9/7gku+Twkalomscz4DhK6lzXxzv74vZkxKa4cp6RRWw3pNlgsirgxh6DQBav7fV7L8/66/e//Abudb7pOSdgyNTcWWE1HG9Z92l4Nd679372WKGN9YBFMu7tBwOhkoohxsiQ+wFl33fzPfe33T44W/2Uuafp40K3AGgE1BQ4XrXkIjgBZd8385PvKvpQNuHezdmPt6u7SYzbTRjWDJvOrDpo+aW5A8GF32fQN4NHcOOxkJ0yJ2wlSVh6jhpDHkEycseIvlfPWv2fHm4V1qURMkIKOOyM9s0CnRqyfGVO7Zt2eDYmq4sgGzz0c33aH/w87D4z5y0VvoDh0rKjW4WJFrCjbIq1uE5g0gcDGiRxHW8ge5oMFudrjI1lqVS2HXMWgwChYiGZagydoksAGPQSIah5KRCVKqG7BJOA8Mnx/Svouxz+csP1eASVoaq5sSVPI0xxLi705xFdnJHtittQZmg8cCm37fzEu93FwsB0XV6wRVKCcPSH7zqpejx0rs3TjmLoKvCICAG670lSF7PnL1//2DkbPzV3950p6k1nydBQn2VSp22qgZ2vmeDi/7Heu/d87/SuyZwYhoy9685siaRc7o85Im8sXR6JGp0yCmJ+V9rjqS/3I3MwPT6Th0AOkGKXAmidB3vhBRGBgIB62/f1f2GnRlkLk5rprOkWdn2btNgf9pd8n0KxwBurFFRkQHHefpZGNTM9YyKntQB96M9a55oO3b3ni+Fr1O7CR9kxoVf12AAr5jRFWG/O9sNdrabnnv2HD22tuv9IrRZC+6bPMczZImg6q7X0GzrvlZPgfAlu06hIlHYASKWE5ikfxdJ1zRHWlLXoX9HRnICYoTOJtLBKkNg3l5kl6i4pGiIIHqVXf4MxvavCABS5/lWQBfGLl2GGd2xacWo2m6wLRusOvDwD9o53q+6K4WgUi7NGVYBHNWwKtG/v3D33r4wMxg7s7doV7peQbdq5SDOkrCrKqLAJOvu2Je+xdSZ/8OWF2rBVSz9pKqBmetZd9X/cu8X9vwMdGri7qGahvkAlmqguOF0TEQsOREz167Mi3sPCDotBY0osBSSoRuiVUxgLYiYOd4thULyh0HQKVUMFISjGV15sm0+k35U86IQNTcR3SBAeIGnMwxJCWKqYZIB97GhvlzrsfVdnwlRO1EGdq2cF6agKYrQTeldaXt87RPfPnZ315vdoPuwMl7jBmsADa7pNYQ1b5wz3mIo3QJ3HV8yBWugIIka8JORuDI3Xa8MAUyAk4HARmz9OzpHlLhAaISgcmFHlIAe544/v/K18dGjQOCZ27jGJCGQSktdITEuAJJj5dnkROufoYxbeaitySTsX2pOBHJ9gUdRqZUI8vlxY/tof9YuxS1QLNEY+1MRzvUQ4zgUtOpEOhmkgs9xrbnLDQSVl/JVnam3VvuDZ+xlfQ92IKTcmvD8CJn7ecBbTobq4fSm0KsnBjRQVdX3lVdmMC0RSB6KDuDrT0ZBIPVFifHekjrHVCXFToh3SX+N53pL4wQu1zSREAUgx3iqyIkbrFHCaZd37+i554mfOvPg06+H5RTojKfFhwkjaQYPJszStIOhoN57nviE36cPSk6+ynM8W8wmcS3AHjs6AABJ9paQRw3qVK/TQaYgYs05VQoihoex8i5FVWCotpT6I9f2JVHyCFB6NWHrLkaHqY7gRySshi+xS1xQOhnC+EPB0tHZJ5M2k8eIIUukIGIZDJRAL4+bTY52nAqyqh8zNWaO+qLXdc5RQ6Sw9Afn1a/dHfqcUWXFiMvSG8qv4gTHYJaJUOgCsKAXBDV9wadsg5d2V/2AuEInJiqUMkZy8ooO0jtfaNvbB3TQpKWtCBymTldyjUEc5v5r5cpkyBGI7m85vKk5RIt2TP7820vn6hDoRslYkNGckBLWNXa33T7pdXeAQRm36kh6qRr6sPY7vZ4Vh2lmxmCYXp5YiE+dnedZGZKv0+X8w8fX7fkSdqUtFIRKGTAUDG036V1pG5UhebhcGI1GKwg7w+8Jvy90TNO/qc4QULIrbV9+oKu3Z80Tb3f9/u9SnWEYUBFliVntkXUXr28FJzh65a9Pg4wsAYJLUDo3IUFKEfYOrFQnMwcmKxSqAlUXlm41iH51xRl+MhAlnDl2x2P5Ut8geo4tLz4wh5RuDct+FfZUKCpxkUbCjhOhX7UFPHKwspLSpTodEPinJ4Pep3elLbZnXPPhze1mjvfdctWfKchIIxDVyDVVnTAIU1JHKaPK+Pfe+//vlfado8qKZc5d2ayiFEMpTrmdGIFAyH278cCWX7cLEj/grvhBxUg1VSGPSUUH4PT7eh544lRYCp2cNSVdOn6pMVKC0Fnbvzqj95Ug6ky9SajjTSNEdKdQISCDwUnfRI32A0rX6Yb3xCz4P1Vn6mzC+Hp/ebAw5nqjsqNx/ntNg22QQCR2oB6OOw+fGzO9F43OA9EB3zMn7fjlIRWu90xwNfjz3s91/Rw6IWNoaabLxLwtG4QFm8zYUs2utMUIpuZygEh2mE9rugzKALAtGxQdZS/t+c3Vhze/YD3+SzCltCACHpUWz+D4SSMEMCj0TlgSKHwlLWMSmGn0EhWDxmk3kyWLQK72vrD89XFh4lEjeeXhtnkKvZVmojkXzQrCkKGECRlayj+qSD2TF0N1FhjKnyxSFgHZoBjYB0N2GZMuQDCjxtCxydB5BDRBYnlshSWiAGfnF4KLxzE5wKflxUeSMtTXAV/it+wVClIHkKVUxHwTUVFBQuov9RUIVItOiBQcoR0ITgkBPg+AMpHTmuDIbY51hSHrPbshuQTwe02Kfsld8l1FbCzDh47CEqM/eE9P6979RZBMBR/RPOMD3BKRF61zyO+IUCMwHvtOOGpCUNZ7AfzDlP9ga1F3QwfChIw02gMSMXKEZ4YhCqfLQvomUJS+iUJyAjiZEWhLASUDCHDnGKaWUfu8dV+rd0npxzQvMwCyqQOT4ZQ14cABhfu7IOH+jlv9sUTq6FxhoP+8HWdmxHGtZ4M+/zeOr9/ze1AQdoBB03BiI5iih6H2zUcealE261Cg9WSwWhXLiXSxqkvi0FkFbRYcRD8RnQbjZTAdVQRPrTiXeL6c/7CcJHKqWKnoKE+sy366+dlNp6jGfIFSPFdz4zizmLYYpb7UKfKYea6XKp7vKoD0BTPLumqtMQkaA27SMHuAy8tfY3vGjc//FkLviXgpqYTghzjRlAKUMkwJhvT5Oc25l1RxSkH9gOYBSgC6lIhqoTpPrvoEoU8BAIp9MYTsEmx5uUkYGwc9WRR2VJWecftXw6wmzSFiEQyqvHSpwKmQtFYJNA6pcjTnJIf7v9/M8da4q76LNdCq4RVyg2flSqCady9JHr0AnYdqkgiLlGgJBCs4QXO4xtoi16LmBOSxkYHgikP/LgCKSXodCmqO3U8Jz/l6suaX1BdAYCreRayO6zwb9Pk/c7x17xcnhNmPf5hKRHqxqtRbjXOchj2tPhV9GTn0RtWT29njNWBA85X33oo9VVLcMaIPPNWjZyqAiQAlSjCRZwxsdLgPCSSQfgi9IqoXiXFRBf3hzBktJ8J6rrO1MuBm1MaICMRWTthfj0YKLh5NPmSsuStkhIlxbiqE661xg86XQXdQoacB9AO4jRh3AbQ0XiAYvq+Ux5mz9+8ftGMysVprZcD/5ePr9/xhelfaZpF105qlKc1ShAfq7Uc2bRRjvh+qb4PoOpO0KaqLiDCjaJPKuBYj8sgHimSZ0qd6epF7sal7y78z8OVj5/ibJacWDiFOnaFtywbY1+r13Lt316p9mx/x6s1XKWnma8HJbFTZoxkM6t3Q9U/Nz7YNcb1Z5AbdsJ8D/keRaayih6UqVGNYh/x/dIO8W1UMEbuSFGqCCUPBqZ6NXY+V0KITlD2NuNVUY0iHYlETKXlE4stz5Lu/KJA+dmr93p6JVr3lxUeSiQMva/f27kJ5X6wIvSeH5giwoTHq4UYG3Sg0ZHbU4He6PifBrRRUnnwOly4pTMZ2bzXAOLljdLDC6YfhVCl+pkMCzbsr/l8I49O1dOm57rXRupV5oFVH00sokCa5XFgP5lYi3A/gTkpxjRT04yfvPXh5tLTOrI6GhCNbHgLVOHmLAr6d63nBpcIfHt+w988nhNlPKoELwmGs0qDy8riqOtNgjQwEnws8/tnGu/lC6efvbDdNd57dSpY+SQlaoYWKgz1Sp4iY9YHtmUnPyWwmdBhM+owMOiECtCBnNdAeBQ7AYQ9YjnkBzrxw1Z4frwJ2+6G2Jsm5P6A686gOxBunoVJDh+ZMJJJafGfZ8buojiH5yhlhoCpcZ9nlgseI8Us96/YcLf/rpp63zMVA7pumxtwXI7iN0LRhq8GOiJrqPRtc8X/j+MbIiW2bVhbG4SuXcS1fbUnK6qWPEujHxembTa0hLQgkJ5CBoFQmo2J3rIz/Xgkl0sgSn5bHd3KS74SvP9OyyB3V57Z8SvPBp3spc37asgr37/ejCPCppgOb30E1/G/wuFZ91VkcTUbPvV3/Z8RDOvjQOk54v1Mp0/hwZ4Ighj/Ze0/XN6Z40XWienw2fGtWU4IrpyaKMgZxmg8cvf3ljV3Hx4iHtkcvQXtGAegxeiw/ud6YNhNHpQ1UzABBGsiAM+P2ryjk+/WXALw4ysgqX3UCIHpswnJL5DAaD7WtJ4M2GXCIUT5WWIgaCPn0fT0bur428l2KhE/bMwqCnET2VQCvAtiLEmN6usX1+fN6N+zdV+qFTjAa0vLVlqQCK2Y0GqIxS2+qgZ3necHlINO7Ye8vo1hRqeznhuVx1WUU5x6K5T+hp19e98TZxmL/PYTDo3dD1zeaDmz+BW6w/6J+4CoDMxCiAf25LS8+khzRF8bEgrA9a/d+sWnfQxtRl0DK0fEJNec6wNjRUYLtAxm8tL6rt+XFlvfI0JJjnODlcc+XiLU9NdGNZbdlHXalrWrw3ZqXsKRd2UvrqNayy7m9vd23fk+JZ3VHR9iT25qV3t3+QNMCzFWpfMBdNTwjCegtc2Qa8JyElSuFPzi+cc/vRQe/q4TGv+VQ24/Ao18zSb4HCsiAQ3DFD4o1/RFEmGPiKirXb0E5n5bknZCCKWXu4RT/gYj+YvNzbR/VgaG/6L0/c2VKLSYAWcoGrftavf0b93Q1Hnj4h0yN9yU4DWYVNqTtJr37PJ0A7GogOAW/lVIGWvClYqQPEUvOwUBeT+9K2wuLFvOiC+dlDG3PNFCjxbJHPAQiE/JyTgb9V8NeZVaxHTJhg36Y3VvGZZcAmjTOKFNUD0eAM7fcI6+fnIC4WUErOMme5kRjQe+dgjh8MbLjBgch3RarPsr1HrsrfkCoHPTAtZ6Ry4WOnnv3fm3NkfZE9z2ZoAgmHhUeh7s6Eo8sPvOetdlj4xGgj2eyeMkSAhaVoPfXC+8n6swcz7p+t8e9bt6Ljg7G1s5Kx3Qocu/LSGheHOb+YvmPKRwfyO4u8Y+Gn7yz3XjJV54KBoIBMNehMuQxISTLqRNzIQUgP93r6r3/qcNjRFKLlYYdnUW0rwKdQHu0ZjtAa460J7rvyOSbDi7dSzVmu/oxepbDA1j5SeZjpWl+4S5ic4fmpXIidAURgUSpE9szDvtaPdy/30dnZzgXvg3SdCRYjoCWq1954EnFbBghkTWrquMGz7or/pd61u/5FRTLiZO9IAoKo9OMaz740H3N3Vu+SvXmH8B0j/QFTgZCiQ8C2YhTjGLyaXHxMzQn4i77joiWmlr7P7mudt/qg5veUZIBnwL6uv/+/X7rvlbv+MYnvyyD7he4xiRiQLQnudqMy27LBquBIAS48Moi92LFZSdDgNPLgbiz2W3ZoPuejJ/dlg3Kv6ZyYsP8dNoUb24r6hmRnj296amh7Nasw3ZMvi9oAg2pIruE0moERU6SykL78FpwOmTvHh96L4omSnAo9xJnkHtIICTHJ4LeZ7dmQwA70/doIUapThHCz6/6L83bmP8Idrab7nsyPggTBWLhem4P91b0zEM2y6mg3pl2DrlQcStZqkWg18+NiQrVWuMGg+PiCu86uS2bw444c1Ph+IBhvo1rjIFq5ag5IqNDDoH4L4OgGNnHUmzPuILvnCrliePWY5BM5NlWrGFYhszO7s4Kti7W9O7dodJysdpS/tUJ6V6bKUTl4sF4NfrSewqoXC0fCyhTNOCojdHGDZYVFb5P4WgIy0BwuTCY2A+A0Lo/GD0WAqUVnKRknLEQEJH6AoH2hqOyKWNkIDgRAO+DgrA7O3nvqQMMDlk2Wo5s+gVKens4xW+TvsBpzklYarkGswYEJiKjvmpw2Q9A1OLVev/a3N328eV7H6oJoebtZipnlt6Vtr337vkT6Xd/z/M9YsGsDk2XRfLNsUuVlgDC+ePrVk6fuHZMEJAJt4dSXOh9RNcUMs0XD8a47Cd3PrepQYFbI4qhWOgwaCQjMgFcmIDmmKwhCkNAIIMJSyMGuUfO1EBXHtyyWhVrNR9RYFXGxCGUZCj0r/fTfj+96HwcOY0wx5hK7DM6nKQgqyllruNoiAolmeDkMgbdO46v/9a5kOKocnHSEly9EMTrrUYD+uJkIOnMqRLh8ahSkIDnE2Guxhm2jpgsg1yysveDOgU7OlFiBOmEFIPhiGBCgFDxetWz6Xl3PJ++peWZtkWrvpVeesfz6VtUdVnc2dDikLtyuNeL6zw6CAbR5ljHD6lQggHg6JkHv/F6VCIeE3iCdBWlTOVjIeFAD0tOfBvdAwNwga8/9vL6rkvFKW5MxrnVCcHTrV7z0c2fpIbEH6mvKdcXTfhfj4lvAhGR1bwTGQqcqbMfSs6zu5v3P9QSHt6TO7Moquar1vx0cC53VlXmzur17c4Wh5BXIQS0VJ4JGQJAL4OK+l2Vz0QBQNP+1jmALkcM6L0WkV5R6p6eDN6NqdlPhHkRoIvjNOxLTAo6LOw47osHuj0W9L44yE101pk5r48Y5B41U2NJHjb1JgknrvLhYrLSHzg2/JWQVWHrNXMupcOJON5cXfzZHgJBgwH3A70PPHkE0cxdrM/bWuoXN1KcewhL0gDoVdNz+bUxzzVigzFqbqMUG0hlYqBFV6hKLpcIKmOS1/AsjcaTtKln88qm7s3f33So7beaDm3+dNPBzbubD285WOOljloOngvy7gW1eMHWuG6Xdy+A6E0yGCDuiE8I3aHTE1WXoB1MShtQkIorKBoF40p0oKhZNwEo/464NQKyBFJ9ve+WulcBgN2g+52T9+7ZXSSGnDQV3p5xd+xL39JcW/OYqU/8mLviBxAo3QjGeSIGyASX/YBT5gHUJh5v3t/WCso47ErbSdPqTDtdWJvtl7x+UEGDU1I8VbJBOyGt+1o9EC1Xv3KC06LmVsmBTMWFNgmtj0naW4kwP06kSYgkyiPewdgE0FEZQQZlFSeNhVROlUoAaaDgqIww5llRsXSJ1TMhxlXoK8fueCxfzL4miDbvDdGNFQcXYZTqcNqvM71R/+OaOZcy5954HemPlDwSGQr+y4n79/57xbOnE6D8FNSoLmZ53CMAONW9vbsw+rmWBsZJV5HlyjM+gobxoebqLrM/rX9THFynjLv92Yduazra9rNNR7fsohwdNUn7eTvXdpoG70dNvU1TktZz0qymBC9ljxaQoflkaD55tIAIXtzQhJRYCwJy1DtmbCAMnLHima8vVdVmKVQeBBdzZwIOTfF9LTFvQMgyQPTKuWVfH4CC+PjGt/w2FIQfmMKJUaes+tYblroa902utW8Krvh+2L/CjWWiJrKuLwiIsYxq6RtNTz+0ORyKniQzCzka6fjGPV9yF+3nS1HILNlrKV4I1VjcdmVRzXHMkHHEd7ySa2y8SDPicmQXlfMuxHP0pcPC8OrY7BJKrHmBaNS/yowBmOiaI+l6JdymvsTJPhVlCKioRzE+3RdobaxMm8JDVaEnIv04vqZcezsyw9yW7jqpMkQdUrU4gp3tJu6eGdtbDe8BcYYHmEAIIdoYHRRuLQK2sYpMPDaYaDy9f+lmb2haTmx7xq361huWNh/Z/KeS8g7ZOvunJslboVQv/YEEV/xA+vxABgKnQ060IKIFVfVVNYi+fJ0ZJwaBNSfCJqJiay9TkYgCT+Px7Zw0tYhDu6cIHSXwwnjzdWVjIfHklhSAJSCC3gPtzCVqJ51syLlTW158YI5Xn/wK19p1IVrrJqDxL3NmmnMORHOp3vti4/629cX0eNJoSkEnt2Vzs3clYSZkJXkbGSoioBBn8JeBnriZULGsxDBNUb9NKu8tMEtOCkL8yji9hTjvT/NMylUayICP2rHXEpUuC+ovgeri2OzoDKiGaz66Z1CEuLfua/UI1BixEVCsQ5WKAUr7tXUsnZCQ6g0rr5cqQ0SbZVjo17E949pnQVliyYG31inp0li0ZsXmCelL45akUdRqo9WxOoiRjIiqXslSNpgUeh85saYDD/+gnZvabxq8nyWHBcFVP5DBwIVnBYXgtvCr2KoJwXKj/5shvZ2qvp4fTwU9CjyN4g5KxQBOFc+OvPjO4mwUkIxRZFi1a1VKtUxuqeKeOQAKA880zk9HVbmdwVDJJT5D9fY+dzUGz9r18WZG886R4QVcQ19qPPTgEqBTi6nyxJpnsxmplnEv1pgiv2Olrow1Jwg0EsycSVRLEe9grBo0QKqX+q05M17PqPISF1oiUp6KHUCYydC51NnE2D5HlD2JM6s4ZUKS6DjQ+xDaPX7pMvrdxYRdoBoBVuL2HGlCZzmL8VS451+d4y8GsOh6SZ8QyEpfoLD89sbutjsy26cIJqdRoZqLXHgPRYh2DCFWdTzBSEV0wKqugsTMDMKM7PXJAFFFbs7VBzf9spmT+CcS3Bpc9gN1qlRyWtersqUKSyCiV0NcxCggxvCt3RkXFRk2mvRqvi//+jgjIgQAyflLlhGwKI4+SYTQARDR1e3GFECCaE6s8ZlNv23ned/rLt+kTqyc/WEoCLjGrCTYTyODEMqqU1B0YpYb7NDmmH2UMPvwddBy/EyoLJWPDb0PMzk6faE4rBm7DBaxHQitilUeKornQU8f+09j+1fFNVdIY4QIlDjEuOorXLG0mJlASkQTt5FFA2LQfRXn1FT5+Ix6jhWoMgTWLGWP5lxX6H1ESMsBPjwdIt1J1QUABJDbOGGSEb8HVVySzgk4IpoeERRGs1LY1+oRUaRzFqOfHXJjnhoPxl7MxLLbskHzs20f8OYmPiIDgVNfhOiGtWXCfnCkLzc60BhGLGJlzDc+RAArXT7zwOrLEz1Xn+xySpkUJMZIRdT2kAhHkN26WHkqVdDVBx9+o6m1/91dickpd2N6Zr6dl/iuxjs2/woo49rRztdXJgdNM0HjAHiNkmfPx86ESpIptBpxymCEsJkKOVnaCzMoDy1/+aEasIbgl0rLCBECqtS/mgD8QoZaZlS6zMugMTgzphRSBvcXdY2cKkmJVO4sCxoO5s40055mZUAUjSEMWvW6ypsMOFXFe+94vvWW0uxdpVYUhYU0UoIA0srL4wakvg6hqGbQPpZC6o76+rmquiQeSCjKyymkTRuTZUflxMbn29Yjhb+QgcDBEd9IPa8iFRsVy3JjAo3iGoVrUnGWWgo8cbY0AlQeBJeeKzXFlltiYhkMnPjB6aJSPE94ALVndNWudIrBnwCV3oWbQAdoWtGvdX2+4wT91h2H0ndlkJEZlDgqKKNlh9FzQSxAgISOTE8du+NYfnry6eOzazT1tM4lIFQFjlMGI5Syh9jQ+8jMgC6B0OJoni1WLUFRrIdPkH06bYHGhN6HfcQLnGgYVxInXWqjUWOIKI2ZaRdcLggKZ2an5ziN+StyTXTdlMFLxhKImHl2gV+oee+01ZMnkG9R5tUUT75FyTKUcBY1Cy5M1M8O8rqMmOaG842VZ9lhJhfSmo0pSUcgCsrrn3DCWASKSomewt1TLn2iMhP5k+GyXEi+PRHlHQHzQ07+uOVW9I2nNZkeTjhmIrcEEC56DfpKscfHE/bFCMIL3U+aed7dMuRmW8Jdy7SBBIDMis5O+eMIFJwyKSfuj66bEmukL6ygVRojwitmH4j6Y3EOgBJyfiCxTEkXRNcR837k2IzWo8guUTArOEWJmMKOhGBYvmXMYRFln8QhMW7FrCElwU49PSVXHmFFvKZBqZxzIUdDF2bSc6ykL0mgJr0B6o0EIs2JQvVDLS8+koyTlZXdQ7PGmg2M2NGBV6LnOgolGvWzybVwjaFYWTaRkSFRAT1fzAxGVrQ6pfnZTdu4xmyTeGraAoC4wRpu8CzXWsN1lilBMznRQhWJIphsvLGjne1GQXWIhxEiDRQqshIExe40RzqWDO3gC4sWc3pX2gLajHhA1Egpnl45dvu3+4qHBI8f0Wfk1u43LCTSX9NBJzRrqXAUWRCIEkRUY5hqDFOCGYZoWPRuFl5yIiP9gaM6flvTkS1vAnVK7BJZBZnQ8iMPzQd0CWaEFKOeGTiPImJxOaesjVODJgXDVxDziRnN2BVVm5VXU9LEo44qzryQnJgAeo8lB95ap4oVMbPPaG6vhCbkiem+cFusl08VEWLx8rmNhwYmI3ueHVujJfmWWEP55WKI8Vh4NOfENtjbket/R3ivFZb3d0T3QLoaEgusEh54Ir3joURLWavS3fDiZdlkCerk9fpij6wM/dc+nFF+iDzWyj9fhWsNg6GuL/iK6wt+TgbknTIUbNNA/ozqYpe4jQw6MRQx2JQ7Xx1+b0lh4gVtIZ0g15i7Gw9sehe2ZQMUNSmpU7rXZgrZbdlAQY2xyrlR24MUp0DQ6ExXO7YskTbZbdkgeTD5ITPPLopFjDpuZEHEddbAEOSqL1LQc0T0OhROSedAsYTrbC0ZgvQHUNGZ9+SKDMmB2wFgF46uuYaHR6j/lSrYpephfpxSxfDZLbEdWXpRJJki0kLWFstKFbLeE8tgIH5xzgTxymAlBnnSlqK0eyzW+4IbVEMTQe+1FkO3AbQwDqls2VbpHaEaMI5jAGgOVGMz6ytmlw5tYi7YzlAIF8HyOLD1MtHZ+EVJAlSgqvhZAJnSXNu0e6udsuZIeyLnztwWi1ggYkJTE7HBjHquw6AGXRuPDUaFEsZQoM8dXt91KQIhFcmIKUMZ1/JM2yIl/S4ZdERK09dxE1Wqtyx5t08s/+TxtY8/Xf7XTYc2v5U9gsRQkSCPSH252u/bV8ZA76kkVeRweHM+hgDV8PPzQWz4H5sPtX3cOfmqAb2iRmuUzCoSuRvAGslF0HuKMVKh0fsanXc8+gKy27LBkgNvrSPVD+mgaMUaNOOgmLjWMKWY3KB7Sq76P+0bWge/5u6edV0bejZ0bSzMc/cYcXcEA/473UDwWUBzZo5nQvn3mSTRZGTACSW5rfHww/ej8xpmZUWpBash3Y1WfgSQktGcgCRsHmdnAAgg5iaKC70PexKXINEcSExkZ7YUlaIpNlNESNf1WgqXXp0Iek9wy7mGvVjZZ3R3huilidGE4ctOpClILEhAKPehmL/myJpEiS3uWliktNcy180nYBl8jcvWCRUdmIFHNTrolJK8ufnww5vQiSm5UEfbAE4sALA0DrEAUdS/knHVDEpcpAq6uyTEWmkm7xFUpWssA0+YfaqhTVxr51VEZxZqEUJz7vDlS/Km43c9/jS03aR3pe2anWsS4flF62Jm2pHmHs6cbc1eHIfHVYc5/dEPjvnqU8hMDyDBDfbnbL39mjIOkjFP2zr+nJnr/Q9imgOJGeyHmI0RbQ87JhtDNqi1Q28zNXa59Meo6452YnM9I/1uvzD9+vH1XV8f79tOr3xqCMAr0de/Nh194+0yGPwG15n/LEMOcJXr/ZYFIcI11tJVeT+Ap9vH15GbsRUjAwGajGUoOQEqFIpjhL0F0PnwxV0TH3pPaCnR+lSslMxEAc68vO7NV4Cu+ItSnOCPWO8pJnWUFPRE99ruwpj+1e7zIUnQAdNCpTWvtEcWsoY4jRCakwYPFLtppAVRsrQ8X5h/O7TjuTDwmQabjIKKMi6l5zs5dyEBUGexjInmxSLChTqutcYNuk+o6PdxyrTEkcZRqHCSreTMz6FMT2261Q2T95ZzkupjqZtrOFLBRbTraOg9QHc+v2lpANyh+Rg0TApGQUDKj48uvxezP4VugUdakf5eKJ/EQd79zutte/vWHGlPdFOmMOyIu0GHNq+Oqg/xKLvyeDkSLOUxOXf0ZwQ6RxwLZFOm7QeVPt+FNR4ycArpC1yoORlvdi5cd4UaOV6+7iNe+sUXsuEfOrwnZLifUR3f8RzPSL/7JL18dvPxNY9/HQpKlxp/JTGBMqGCdoOd7ab3nsdf6rmn68d0KPgv8CiARwTRmIoFxDrkQIp33PncpoZMRE+Fa9cqa4w5hEwQKKWYBFwHgq452m3RAUYHOFyzdjNlVBtCjAmqq2Oz3lsGlE6V+opx9kFJtXlNAqrxhR1DVaZk6LjSZng9OjgNWBBUSVfCxgCZF8uoeZcX8U5NjCYMEW6qkotB4VyMcYVrrVXCz4M6Be1AWiORx+I9RfeFXWmb3pW2pbWPZFyy27LB1AS8US9IdBXXlPoola+7IcC5r4LoM1xrYlGLEchIf6Dk4R0rDm9qBk0TPVyEhHu0gmpi9IKK0Pu8DBHReexsN1h0ntAR6o+1vPSIB4L4BWrnBlurlRJAK5QShmXQnaPawt6RsPVh9DJI1yJQmnYAF+5H4/oD37B9BgqKtOpKGemaIw8tUMWyOD344txbUdGiJNcyjoSLih6PNQs7GnRXlPKSYrZHZkbUhkQsQ04RVa2KbQ9bfvBkCG7NkYcW5B3SOiSESuq6ozOxBs/IgP+RnrV7frV8uDqLcUhESz8jekkVnN6d5uy67N82Pfvwq5Sy/wLLXpxBVACsBRGutUsKA4U0gC+Hqf/scSuWZ0KkujxWzX0Yfm/I019HB95V1B6KKIemziUj59G0r3UuZrTZAYX2lAM24lo/L1xonc6nWMKOZGTIKSX4vpYDD997bGP22eH16EQWyK3ct2UZGXmL5gRUsaYRlAyRCi64ofy5Uumyc9yDVQC6CKJ4w+FERvoC4ZT5L41H2rqPU+aPsxin6NXZCQBS/NMlB9bXzfHmrHXQh4h4PQL5Ws/6PTuhSiBSTCRRz7S6OCpAcQA2OUEg5tUEmb91V/3/RkQmxlAyqWpg6r2Udzn4MIBfakc3Z6bZWyVQI0yMe4hEYSVwZ17asKd3VA8AxwDXeGTLA8y6Q4YqVE6PqLi4ho0U5Gs9d3z7aru2mwyVzq5w0FrTlg4FTaVBa5q+Mrw6uTLEg5dGUgeGWWouoFvJ0IKZ9OAREYFPeo8Gz8RDFU7m1GaOdSdLJE4v2SDxank51I6s62ZczpkHTS0vkEEnsQb3VB3P8YzrCz7bu37Pr4YZREYqIuUlSBZZWbNzTaL73ie/0vTspg+ZOd7fhYKdlZc6lSDwiMnwdwH48vgN/RlacWaEaAkk7swdGRkIxNTbdzZvb/u6ezd9BBw8z0Os4mmNMfZOBH6+Z8OT/z4u20YEfkBN3WI4tyja7Ig15MkRlVJ8FgoCoDRUmEfW1s1ADUuJyVNrPtt4YPMvksVBG7DxFYuI3CPk6U+SNUt0UBRc6d6ISi0FnDq96amhiaD3pYOV6EQs0MrIoEptrfmj5sNtj6qTf3SwTyn0coLYVxYKyC004LsBvQcOG4hovRKtNDUWnGL45/Pft3zvQ186TTQ02aiAqt4eG6loiSQvfZ5HfcfWZU83Hdz8ZTPHvlOuVv7+kZLRAadE+r41Rx763QxlLk13PlJVW2IjiJ0qGapvOrTlQ8p4xom+5hH5AFbAyTsB/RCIG5B3Cq68rKiBEin+CQAy49CNNR0sLFAyCykGMo8I4uVrXdgPyygUWHO023bvbHegMyu4xrAMBBWfz+Eoi0IjIvDsZLOwvnlcBgIfRF4sVpVrRa/lMcHp2Rd7F18aRZU6Co4KfZgSHHeIUijBLP3B2cRQ/qdCzrfMxCXK4fLiuNa9vbvQuq/V671376ekz/8C13smHA6s+ESNBhfpDeXsy5hlltbonlIzlaeR/kA4ad5kk/SYceY58uh5Q/w8JfCvvCD5WNPhze8EQdtHlxkj8IM6t5qSpgg4qVQzi6SgIF9nBr1HSJNECZsAk4lOf4p1+OdEyfLtptZ8kYSeC0ieM0l8y8xNdBLREh2SuD3UIsvByYmg96MO1udmIUolGQiEa0ybmZv4mPX0GUv6vFDwPFSftzDPmlrzj7bB+03TYL+HErxSfYX0BX5wsRAARFxvUxPPX5U0zhpnNCAOnCuyyxDjT7VQOXKwuKHEF+E53i25wP4IMPWAdOkwBVbFolgjkPpKxLTENJiPG4NvWeB5VXmODPbwPO+XAWrQvFTsxAB1VGNJ+oND84Khb0BB2DbiPIlKuzKXgMp6lCFAReHRAtJgFbZHApsE7V6bKURl5dao5CcxMNxGcg5cHGUZTw+PIOjo4N77Hn9Jne6lWqPXTZR1mvRaUD2NIo8nYWSPrEym4l6NOXuiqkopQ+rkfzz/4NOvp7emeVwAr4KGdXkiBNcEaML9rftDdJFnf1VyQQ5MXDGSUYmRFxBwZ8szbYtKPxOzy9Qa7RYfs6C1JoOB0yERMNXAUA0AyJArQCAEWg4A50dFgsOs9zQD3kEYzTuI5eNj5kzieCEnrlQfj984Js2LROtRS4aT6qtKnx+orzMAApVg8ZMS+ZZ6HnDPSH8gmOk4SvR8pc8P4BTESBBzHZhqIWFDPJTzCJwWRKI8O2JF1wQKlJp4pTolUslaGRHtchyADZG+fOyOY3nsbDc9a/c8LkPuaa6NNzhMINK8gKA/uebImkQUSNIkRagoB6CVcYVYQYAG0R4pqBLBI+Y69VXdVT+Ai7lvFKAEEZj+ZP/9+/3IKeuYc8B6NbDEJRxgJeUzw9Yk6a9WH2pLNx14ePGqI+mlLYfa0k2HN/8VG/pN6Q+UKq1MRYwYKrgqIagOE+rhbQ17lEz0F8Tj1K9vJL0WExCpVJQrxfOIF2BX2irQHEumQqGcYOOu+q96SXwGCho38ymWFbZnXMuLD8xpPPTgkuLvx2WqJwgy7dx7z+MvwdevcL2ligdri3BQQ/P9hNxW3sDHbMPvCa+FAywz9mYGBIZThSvxg1n4yhrRy0ycLcWXTCFDgNPLgH9u0s0+le0IM1SXTPQDyEUbcCY1dh6xHqVG8iwEJG6KAfQo8Jnv+8+r6AuUZMQZrxjLER45RIGWP+fhhjiZEYCs8G89JLSmXMJmrDL4W+YocBvisfRr1JfqBYCWjX02QrF9FCYm/CsckHbcYO/Myfy3h+vZzpNReK883DZPoctmRCxQvkeKa0yg2GCDEBrPcsV/sdAf/DM6wBNVd4xxhuIOkw+JkscPWI92g80xI8ExJHi3qffer4rUeNRP0x0QJ8WZ+UHh0qTfuS0boKODjz2/7PPuiv+0qbcGotegihWvYUHj0NVx+ea5owHzAFoSDySgjmoMFPi3F+7e24dM+1jhwMiJNT754JLm7i1/q36ym8nrbnnhjV3NB9oeCWdNxnFmi0KYNQg7EWrKURxWEU4yrPDqUZIrmC34fYQWewkGOmvS8uX6Q0QsOacQHXdQuejYBNQyE/oXJTp3/7qVr82I9T6a93KX8ucU+lpUrprd9ZgxJ2c0t2f1+BRlVE3vTpv99+/3ifAlSsXOdie/p8nuK+I7JZCX4Kh8HbHcj2HpT+VuI8SF3o8cEJ979YJAQf24+nm56l6mJJsiW1/lxGlQCH5u8kw/Qog6vZVA8+L2ea/RvlEyRDD6y6c3PTWEe9rH6fWFAZzvMKRO41cghpxoQZUMNZDhOs2LylV/BqxHJSq2V/bfv98vL8tN8P4C2zNODN6vBcmRxxynrTPbPkx9BZjGBPJcHtnlrDQQ6VwVjUPUS1AFM3YDoDFotxJ8NF1PtfYxM9f7cQJuI6IFZGkz1fK/NR3c/DYQxg4t784KCOoLP+36ggIRmUofaJGKSBS3Xgs9qNKisuyFL0QVl3SmR4kDwSUWMy65bQSoIVasjMU7GPVHCDiVCQdGeSay99AOPr3pqSEAR8mjm6nWHkGdQZJ3AWvEYDIJ+0SxvBiQ+ZT0BwEx8WxKAE1zRQEGq6AGk7DeB0rLuc7EUgYvCruaSOtpf2uTpHenzbmNhwZU9W8oZeJK5Rjpd+Akv/H2o20PTkwZF95D0uptXGtMPE2/awEz0IDnekb63Bd61u79YpHZfqKc0gguQvUKGYpH9UXEEWeslmR4wgydZsJ6X3QCUwby0fM5sW7PQcn574GFo6Qxqhpc530/ZuYz4KjHVxYMcXlkZ4nqQXEb88SaV8DnYwB09GBpenfagKBDLnifXZjYGLyWz2ugqk7V9TufQl2f/wltN2PkFqLo3g8GzxHoLHkMxGFNZoApima3zvYih9ec4kTWDcgZSjDFilynmsoHzh/7167Xx2RLw4FCHaDxeQfDgkjvbKgYFyUiiPB/YYiUcLOU28tY7+kcX5WpiXyjAOvkusefQ6Cf4wbLkaO4rs6XDEFdtIcz3eP3SNU1Rc9RYx0WOYFzdLLIbZndnRUA5Dv9W3c16GNmE+9wVkcpQxLgZ6Zi7hfFDO5h9jXWOGmsDARn/QSFILaJ1AuiPd674ckLSnQCHs1MRmc2KxAEqA5TdmE6clDabnrvfeoLwaB7uxLOmHmeDeMdDaLyul7HvU8I5ArgvVrevhgzEE1QL/aSUSQcaPy+cjj6OGzWW9RXIYIpPiQCrAw5JdBdtx84tRSEkcrOkZLz2fv3Dyr0UhjlaNzrTBVVRWf7YGzXdtO9NtsP0r/jOkOqs3nQRaUB0pNhCXbUYGmUVQ8F7lYFFsYuAtBI3sHZkLVxRj4nfX6O4gB1riGSNyIfPftC296+aUHC29eEIKHA/XcZcIPkMV3X+ylF1S41oZBjyAkWVyJDYYjEl/5A3LCGV0gvxada956BYifVG9J4BNBG+gMF67tWHtjSiPaJB6RJKKRYu9HBj6jAMis0r75uf3nNE2dxTzuhc5IgVSMgm+heSjAUkJuhtaS+QhFUJuxKoTM7ce/efy/0B2+QoeAvySJn53qWajjMGlWdQoPiF8r+v/RnM4XXUUQCDZw/ec/iC1EVV8Z1ZEIaQGfG/846BaJLJyBODTNwF8ypDSZVcibIjHa208K1yciAUPdMyRbsn7grwRlOGjtbdWUtlv2ETo4riFfkHSSs4Bpj4WLxDkYqxuiZGfR+ZBZz4p4nT6rDJ3mOZZ3NOnskBhT7X1uCcsR6n5kGOzt1Sjvauaf1qWPqu1+kesPK14EIeHQwA05MOpQPNMIhFhdflKWeX6z5C+MQJ5Mz8ucyGDjSGNR1BNJwzjTlsX4QBG0fVeIq3oMyGjXePczm9goowUwWIgPuh3s37unCrrSdkl0lmvhmwj+Eg/pENwHkj7UgYDLHJ4TeT+bMdrabU617z/Tc1fUhKbg3BFeD31NfDgAIuMEaM8ezZo5nzVzPcoNnTUP4/2aOZ+1cz1KSSQWF+E+zGMjj5ZJgJ0aDPaIUTZx/FaoBKAZUOhykRGBo0WRlDzLyJbLEqlSUbBGFFrjBEhG+dbz5m+eg4BERT1EiZe9DNaRYGDJ8UBw2bii0/5pkZMWoIbOdX7w/+xocfgIMlORpZieJgDJ6JyvJKKQxLL3G+JkRowPYnQRmiZSyPSPoACcSqd9yV4NTXDNLzj3qccFQ7J5BNE7aU4l4aIYyDrvStnfj3k8EF/1P2PmeB6BwXTKzMKp1RJScoBQkJemTWBIZ0YA4cDIEBJRlqRGs/+TavQfg45vcYCjeTCexDopC8Z9XPbthXmb0oRS1FUhpNZzemO6YQiNGEgvCZRmQ7z3euvdfsCttsS0bTK8kBz62Yc9Tkg++xHNtsbc00+uKR6JeHHL3tc/6cnZ0WQ7TVZ2PxqR6Nz55pHdd12/0rOm6jwgbtN9tl6v+b8jl4E/lqv930uf/s/T5/+Qu+X8jV4M/CQbdrzgXvJEIn+N6izjBbKntoXhxPK1GW07LU5Os7yv4uStsIkkMqgi1KJxgpiHcA8XXx8gmbMs6dIB7nrvtc413vvJ5b1HqUR0IoAqYlEm6weB1Zv2l8OXrGB4wLmOs8GrtCrDepn7lsyWlqXbi1xCfrQLTrSv3UOaxxv0P/4Rp8P4WgUJ8CYjizx9RxFag6nomvX6KykpxJFMMkRSk39eaMxNJw8cEfdDz1Pl604HN71FPv0EeJ7QgrnImjuGeBXlsJFAfInkyXF9pnk4IZUaopFeFysiQd7ab4xszP9l8ZHPSzE/8mLvsS8i+T+aaFLigQgBzjWXpC+djUF76jZzOoiPpepJgWfj+UtzD4ng5iXjpG3anGciKKP6MBW+N6WRYCs6Zed4SvtzwHgAfw+60AbJB8R6WHHhrnWJo2YwkaOI6MKhjw5YbrJWB4AnK4UO99+3pjij2gkprVP7z+BD1B/dxrblNBsUnghfzuoSTxmgglRcqw2oOaSDnlt7nnX9hVFluIkvvStvs1sUKykiJvgKhk07vTnOWssExdHUD6J7OZTQf2twB0VhPlIbLhgfG3VTl3/X83cEVABfCWmRlTagQ7QQQ6M0gaHZs6qrYEc6LHV+/t10uF/6rFLRLfd0nQ/7fyBXd9NLavQfCE7hzxL9Nb00zFGSMbuF6z6rEIEItCjQGk0y1z1pmlnHt2m6Otz75SRlwj4Jw2czxLFRFKxcODbW0Caq+klpzajyW9rKyUhOchnwIYQQ3vS9SRwaOmF4/7a6cn931CBFQvRv3dLl+1w6mIa6PotQwW9XpiTyqU9WAaq2BRw6g7yeifzQNRlS1MO17DSe3oL6QUDj4XZFkDkGLTr5n3Z4fD674HfBIud6a0jOO3xfR8PrCvkNIUMts53iWEsz+hfynaSjYBVXC1rGMEvWBuxWE+eqLRKsmle0DOECPY6L5IgUdv2Qec/3Bc5QyDMCv9GcQQTXnHBF+ctm+1loMK0gTAMzhoSUgvSUa6KaYLkmmLx4arjVZIjvPs2pw2fW7X+lZ05U+dl9Xd0jekHFx1OJP3b33TFCQ71GHs2au9cIqlLpp7HmN9lLxuozk3YvqcBUMF4oQT3e/q4OBA+FMlqKAYRqW3ZYNovvWkLC8OAYEyYaZacjMGpFcF7+K5ObpXWnbuq/VS+9K2zu7NjWo4i4txCUPJyMDTlXkmVEMNiNkXDScK+gMcHDzCTJ0pxK5SjExMhAIMaVbDqaXH6PO02NkAmi4z3UMXX8M4I8xkhxjXCaQ7NatAsqqHsR7wqFGkgqn5QEGia9XE2peiZVaV2ilEtS92S+s2vfwcxb6h1xr3w5L0CEH9UXKaWZonJ1NCgYRkyGYuZ4NLhVOq7MvFFW8R3xzEUWlehunDGtOGJWMZDplszAB/2zuMMKyEs9AVnHCTPUEZb64+kDbNpvkj5l53n0oKGTIheUGwoh6mJavg2HmpDFIEGTQdcuQ/Pzx+/Z8venQJgXTBzhlEhWyM7DrDwo26Z6bmPV+6iFpKLiXun676dm2b4i43+Y6+yYYguYE4UGsTkfdF8aZnaAiAw2DyWOiBIGYIIMOGsgLblC/Bh9/37uh65lxJWUy7QRkwIwGM8dLyVDlzNWkSJAhkNK+iXuk7YxtmUAPbPnvlOTPAfAqJkJTMHkM5PzbUwnbAMJgJFdDQAaO9Va2Jql5icfxx0SUYNKcIAQfjL/2BBAMG04ZA0uQgeCiG5RP+3n82csbnzg+LGsSk2C8iHS9N3OgZd+mLQLzcW6wb4UgfK6j9ryWV4+IDKUMmQSzG3KvB33+J3jI/4jWeF+wtyTf5C76mPb77ZTNXA8y4PaNm2mPU6zAznbTdMfZDzCj79j6rs8U1yDM0rYKqFOHs7SsZCfSI9yVttiadc3PPryOk/ZWLUgMqSUIJZklJ718bs5hjEPUQCPSyG3ZoPFQ2+97ixK/6l4vgCqaTSeoE5gFCQQX8h/t3bDnZ4uM9xNg/DgkE468fcjJKOMjgDKu8VDbW2yd+brmY1DLC0B1BnI1ONyzrmvDjAZ9K44khteg+fCW71bSH2fQVkrSYkpwmPfqWLkrIkB9hQw6wOAcWT4SFNwvnli35yA6OhidnaN0hDoY1CnNz7a9k+rNb0vOJUinSxpOISKIcDTIFX7x5MZvncQO0HTKD3HXo+WrLUldufS9MPQ+OH2A66xHjLHrQYDmFVpwA2TokDr5x8He3CfPvmP/IHalLXZnpenRto9wDb1dc0rTIkonUkpSQfL6u73ruv55xk67/BkfaXsEgh9Vgy0MWkG1BmPua4yic7hH1RdoTgSMEyA8B8GTJPqNhLn0TPfa7kKZXtTYT4ui5VUn0knT5/6ck7wl5KCc/h6gFKsblK8dv2R+CVuzbhKOVAZBmvZv/iDV8U9pQZKV+TFSSpEgp3/Ss77rr4p7t9iDaj7c9qNcZz8tfX5leohFRfFA+4j0BFleR7VmXHI04hBbJ4NuEEzPgukLhcHgn0617j0z+pnOfM9H9wegqXvzo0z0Uyp4I9daCy7L3Sl67wOFDAYOhg8T6z/nB+QfitfVfKitlZL0UfV1AWR6ex2WVEW7AodfeXld1+XJzr+iH2g+svmn7OLUn8sVH+rLXnH4aKEv+NdoLjS0XWmbLgY8mTKkeqabSvp5UU+x6VDbF02d+V43ELiK6bWgAc/xrLvq/3Xv+j0fGK9XSWMOmEOb34qU+ZTmJFBVU2mUyoZUBb76/EjvfY+/NO6hW8kndoDSO9J86lCQoTrzBgyIU8BUgkUhUEB1nJRB+Uzv+q5fntVNOl3JTAzru93V/YaFga25TwNZpwGWAToPiiQRDQlkkAhDpPQ6lI9B5Fjec2dPr33q4giKrymsVVu9/bvrdbrozDSALGWvDwKv7MUGgDsOpe8K4B4mQ6sRyCIF1REQKOtlKJ0kj15AgO6edU+cKn3G6IHUDjC+t9Wgb4p73g20NvTT/vv3+5Ws57TuCZ2lZ7zmSLo+J/5dJLSGLDWq6BIoUgpKlPmOQShdAenrCpwng7MSaK/O8U6ebMzmRuRB2m4yWKOjy+4TPk9N22n3gXcDaOgntH6Pm+7nj1i3fa3elOs++mfdv3/MYG3xEG061PZbdq7tDK74AVXCa6kqVGtZBt2B3ovmDc0L3QYArWBqhupilbA/RYSALHrF6REQ9vWu3fPyiHNwR0ZnPYjrAGPH8Blw++E33u1UHiJGEwSLVbUGij6yfBoiPUFCDp2888kXSmtcUhEJf9+qrd5+1E+9b/f3E1qbpq8+UpSCOrh5D9fZB2XAOVNrEmBAcu4FIvwjGfPFlw5mD2M7pvzMVcfTKdMvHzG1/DPSH8RTVIEKJQ2L77b0rt3TNd4w+rgefc2udL2dn4j1cp/DOTTUpszAVRecvX//4GwdfKsO7J6TO3/JX5iYT5Ve2zkA8/oHeKnvDWW3Za8jXHqUFZkMtsdwosUewlSZwygnUfFhvKMT1yQTG/d+yrLy6f6b3WkzJluYmGUB12ytrsUzHnVt6d27OXthcdiPq8TZzuS+KlnLuOs+0XVGAWbTwba/N3Pse6XPD1CZI3PcYI30u3/rWd/1nyrZi+ndaZOdLAudzYpEBXs+LOWVXdcoh1jRc51qH3WEaPGVB7Y0eqzdIKSibrKCoJQ0hpMM1x9AFUeheArAITg9BdB5Ue3XhJJVzAdohYIeIMKbucbcJQNx1NuLagOGdUCe6dnQ9UB5QjAL2u1Vm41DvAiZHy2TPnKIPKMTPbwp6YzikSDdiPXgojLteGuR3bpYpxElV7pC15Y1QkFABxXn/SaayZul5z1R4BOPD/FG/ayoetN0aHPW1Nk3Vqo/qNDAhCWoj/Wu2/PTa462e4sunJfx1j+9+zxNc19dvz2/+zyV9P+2ZmXcEnLcNZ/OfopKdk2HNn/QNHifcFd9R+WlXYUoqRDIUopBCQ6fo6/QgiBEmQLkMSjJUVtAoLmY2pZlwYkOyLuPrXviX4pZ+/Qc2WwMIc72oTg713RzUN5UrWpVG7ekteZIeyLnzh7lFLdovjJggEIDM9ez7nLhV3o37P2DiQ69qk3SAiFI06HNXzL19nukf8JAIpy0i6pDoWZ6xA05jAQVJSiFfx7fidVZ4/qDp3tfvPVhtE+Ao5hwk1BJ8jL+F67BsPHMr6nqxKpWtZvY+nO9CwEN5+A03qwoE5+YFWaa77xAQlpebFtEii06JChRBowvMccEsmEPk8wIdGlEcBzJ5XDs4X9DEF8ErD+J7RkXolrHN64+wapVrWo33kL5FptI3kaG64Y152LMigpenjVmmu8UC5kySPPyJm6wcyUQN1tkxTGZdwIzxzOak47e9Xv3QSfvx1YdWdWqVrWb4CCNuEOFVnINo2Jat4iZRgs65Hvu1Vizgd/JFhICqCreASalG0jWrArfzve84FLhs7337vmdCAQ06X6oOrKqVa1qN9zSw+XBRhiqnPU+ItVW6GvBFT0/pSxP1UaWFbdn3J3PbWogoTfrkCPoNaFamw5XgW/meZ5c8b/GNQ3vC8daMlOy/1QdWdWqVrWb50wlNMdm1DYEIpwtDe1S1ZFNz0Llh6CAN3G9XaL+DSgrFoma53meu1p4LHc1+P5jdzyWx47OaT3HqiOrWtWqdsOtqF1HRKshMeRbCBJmZFF/bFz16apNqpzB/A6EbEMO11d924FBdn7Cuqv+p1e8Zr/39KanhsaooFQdWdWqVrWb2MJBfwWpYmWobl6peEN0mmnoyKYry1O1MsJs0c/JYBBw0iRmRXZmGkwsUHWmwRp4NCBXCr/Qu7brfdlt2WAi3t2qI6ta1aqGm7RHAwBY/uRD8wEsQ1A5QzoVOVUJx6sLihiE3h3cu2HPv+lA8IhCX7HzPFvKlmZTay/U8nAQFa61zPXWuJw8JgXddGzdnj+BgqGV87xWHVnVqlY13AzQ++Rcs4wYcyvVQiwBFkQhQieqM2QzkFpqffIb+Yv+g8Gg+2vYEAIPQ6TDskKViXtqUUookq8xIG7wDNdblkCe1pzb3rvmibcdX991CLvSFgSJ09u01SdYtapV7cZaqCZPwrdRDRsZqJhcVkFkZNCpgXslYoytOrI4mdnOdnN6U+YVAB9oOfrGj2vO/QKAd5q5XgMUIRWVr4CohGj9iZ0OKRhMTAmmULUekP5gSIbcN4TxqeP//MQX0BmWlMPycnwWlqojq1rVqoYbDTbIAhB1TcaYymnkFIAlaKD9whLKsIzSq6paJWVGEDLtfOyezLMA3rv66MOraFDfrkptcHofgJWU5JqQ14NKoNERElQKwFe4IedrTl5Gzu1jy18v5GX3qfv39owjgTSj51V1ZFWrWtVwk/TKmsGAEpQqnSEzRBro+QWF4GK1SYZZ4MnNuFB+qgMnqPMkgI8B+BgUvLr74RXWYbUOYoUYXaKM+XBYAIIHoTwM+kj0tFr0EtuXll/AiRGclwoG2gmUcbMlp1V1ZFWrWtVwU6DmlIah95VhFpU8Agr6yv5Q3ZyqM2Sz4tAE6AQ6wOmt6VBSiDLuBJ48CeDkdD+mBwB2tpv0ovOU3Z2V8HMzs3ypVata1ap2EzDfNx9o28d1plWGKpNvKSkIX/H/d++GPT8ynoJw1WbRZ3SAcE87YVEoOzOeFM2syxJVM7KqVa1qN7sTW3JgfZ0SlqqLWNepYvQ+iOg4EKmdV1f22j2xTmgxoxpvnW/E2lfh91WrWtVubIQPYC5Si0F6i/qxA3cVaLU99h1qVUdWtapV7cZZpDGlnl3OnklEYOzKsB4K1oIQE79SnSGrOrKqVa1qVbu+1h7+Io4Xcq0hUOXyLeQxS84FjoPnAQA7qvItVUdWtapVrWrXLyUTKCjJwePBVf9xWDYVMEcoGAJLQ6TaceKeJ09CO7hSeqOq/ce3/x+dfNPH7z9MCAAAAABJRU5ErkJggg==';
const GRITSCH_LOGO_BRANCA = 'https://gritsch.com.br/wp-content/uploads/2023/07/logo_branca1080.png';
const AZUL_GRITSCH = '#213035';

// --- Formatadores (identicos ao semanal) -----------------------------------
const moeda = (val) => {
  const n = parseFloat(val) || 0;
  return 'R$ ' + n.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
};
const numBr = (val, dec = 0) => {
  const n = parseFloat(val) || 0;
  return n.toLocaleString('pt-BR', { minimumFractionDigits: dec, maximumFractionDigits: dec });
};
const fmtDec = (v, dec = 2) => {
  if (v === null || v === undefined || isNaN(parseFloat(v))) return 'N/D';
  return parseFloat(v).toFixed(dec).replace('.', ',');
};
const cleanCityUf = (cidade, uf) => {
  let c = (cidade || 'N/D').trim().replace(/S\?O/gi, 'São').replace(/SAO/gi, 'São').replace(/\?/g, '');
  c = c.toLowerCase().replace(/(?:^|\s|\/)\S/g, a => a.toUpperCase())
    .replace(/Sao /gi, 'São ').replace(/Candoi/gi, 'Candói').replace(/Prudentopolis/gi, 'Prudentópolis')
    .replace(/Corbelia/gi, 'Corbélia').replace(/Mambore/gi, 'Mamborê');
  return c + ' / ' + (uf || 'N/D').toUpperCase();
};

const calcVar = (atual, ant, fmt = moeda) => {
  const vAtu = parseFloat(atual) || 0, vAnt = parseFloat(ant) || 0;
  if (vAnt === 0) return { atualStr: fmt(vAtu), antStr: 'N/D', pctStr: 'N/D' };
  const pct = ((vAtu - vAnt) / vAnt) * 100;
  return { atualStr: fmt(vAtu), antStr: fmt(vAnt), pctStr: (pct > 0 ? '+' : '') + pct.toFixed(1) + '%' };
};

// --- Dados ------------------------------------------------------------------
const gastoComb = parseFloat(d.total_gasto_comb || 0);
const gastoCombAnt = parseFloat(d.total_gasto_comb_ant || 0);
const litros = parseFloat(d.total_litros || 0);
const litrosAnt = parseFloat(d.total_litros_ant || 0);
const pm = parseFloat(d.preco_medio_litro || 0);
const pmAnt = parseFloat(d.preco_medio_litro_ant || 0);
const totalKm = parseFloat(d.total_km_calculado || 0);
const totalKmAnt = parseFloat(d.total_km_ant || 0);
const custoKm = parseFloat(d.custo_km_comb_medido || 0);
const custoKmAnt = parseFloat(d.custo_km_ant_medido || 0);
const veic = parseInt(d.qtd_veiculos_ativos || 0, 10);
const veicAnt = parseInt(d.qtd_veiculos_ativos_ant || 0, 10);
const desvioAnp = parseFloat(d.desvio_anp_pct || 0);
const frota = Array.isArray(d.frota_ativa) ? d.frota_ativa : [];
const postos = Array.isArray(d.postos_utilizados) ? d.postos_utilizados : [];

const kpiCustoKm = calcVar(custoKm, custoKmAnt, (v) => 'R$ ' + fmtDec(v, 2) + '/km');
const kpiPreco = calcVar(pm, pmAnt, (v) => 'R$ ' + fmtDec(v, 2) + '/L');
const kpiGasto = calcVar(gastoComb, gastoCombAnt, moeda);
const kpiLitros = calcVar(litros, litrosAnt, (v) => numBr(v, 0) + ' L');
const kpiVeic = calcVar(veic, veicAnt, (v) => numBr(v, 0));

// --- Componentes de layout --------------------------------------------------
const linhaKpi = (indicador, kpi) =>
  '<tr>'
  + '<td style="padding:11px 16px;font-size:13px;color:' + GRAFITE + ';font-weight:600;'
  + 'border-bottom:1px solid ' + LINHA + ';font-family:' + F_CORPO + '">' + indicador + '</td>'
  + '<td style="padding:11px 16px;text-align:right;font-size:13px;font-weight:700;color:' + GRAFITE + ';'
  + 'border-bottom:1px solid ' + LINHA + ';font-variant-numeric:tabular-nums;font-family:' + F_CORPO + '">' + kpi.atualStr + '</td>'
  + '<td style="padding:11px 16px;text-align:right;font-size:13px;color:' + CINZA + ';'
  + 'border-bottom:1px solid ' + LINHA + ';font-variant-numeric:tabular-nums;font-family:' + F_CORPO + '">' + kpi.antStr + '</td>'
  + '<td style="padding:11px 16px;text-align:right;font-size:13px;color:' + CINZA + ';'
  + 'border-bottom:1px solid ' + LINHA + ';font-variant-numeric:tabular-nums;font-family:' + F_CORPO + '">' + kpi.pctStr + '</td>'
  + '</tr>';

const th = (txt, align) =>
  '<th style="padding:10px 16px;text-align:' + (align || 'left') + ';font-size:11px;font-weight:700;'
  + 'text-transform:uppercase;letter-spacing:0.04em;color:' + BRANCO + ';background:' + VERDE + ';'
  + 'font-family:' + F_CORPO + '">' + txt + '</th>';

const faixaSecao = (titulo) =>
  '<tr><td style="padding:22px 28px 0"><table width="100%" cellpadding="0" cellspacing="0"><tr>'
  + '<td style="background:' + VERDE_ESC + ';border-radius:6px 6px 0 0;padding:10px 18px;'
  + 'font-size:13px;font-weight:700;color:' + BRANCO + ';text-transform:uppercase;letter-spacing:0.03em;'
  + 'font-family:' + F_CORPO + '">' + titulo + '</td></tr></table></td></tr>';

const linhaTotal = (celulas) =>
  '<tr>' + celulas.map((c, i) =>
    '<td style="padding:10px 16px;text-align:' + (i === 0 ? 'left' : 'right') + ';font-weight:800;'
    + 'color:' + GRAFITE + ';font-size:12px;background:' + FUNDO + ';border-top:1.6px solid ' + VERDE + ';'
    + 'font-variant-numeric:tabular-nums;font-family:' + F_CORPO + '">' + c + '</td>'
  ).join('') + '</tr>';

// Veiculos abastecidos hoje -- diferente do semanal (que corta em Top 5),
// aqui mostra TODOS: 1 dia costuma ter poucos abastecimentos por filial.
const frotaOrdenada = frota.slice().sort((a, b) => (b.valor_total || 0) - (a.valor_total || 0));
let rowsFrota = '';
for (const v of frotaOrdenada) {
  rowsFrota += '<tr>'
    + '<td style="padding:9px 16px;font-weight:700;color:' + GRAFITE + ';font-size:12px;border-bottom:1px solid ' + LINHA + ';font-family:' + F_CORPO + '">' + v.placa + '</td>'
    + '<td style="padding:9px 16px;color:' + CINZA + ';font-size:12px;border-bottom:1px solid ' + LINHA + '">' + (v.grupo_veiculo || 'N/D') + '</td>'
    + '<td style="padding:9px 16px;color:' + CINZA + ';font-size:12px;border-bottom:1px solid ' + LINHA + '">' + (v.combustivel || 'N/D') + '</td>'
    + '<td style="padding:9px 16px;text-align:right;color:' + CINZA + ';font-size:12px;border-bottom:1px solid ' + LINHA + ';font-variant-numeric:tabular-nums">' + numBr(v.total_litros, 0) + ' L</td>'
    + '<td style="padding:9px 16px;text-align:right;font-weight:700;color:' + GRAFITE + ';font-size:12px;border-bottom:1px solid ' + LINHA + ';font-variant-numeric:tabular-nums">' + moeda(v.valor_total) + '</td>'
    + '<td style="padding:9px 16px;text-align:right;color:' + CINZA + ';font-size:12px;border-bottom:1px solid ' + LINHA + ';font-variant-numeric:tabular-nums">' + (v.custo_km != null ? 'R$ ' + fmtDec(v.custo_km, 2) + '/km' : 'N/D') + '</td>'
    + '</tr>';
}
if (frotaOrdenada.length > 0) {
  rowsFrota += linhaTotal(['TOTAL', String(frotaOrdenada.length) + ' veículos', '', numBr(litros, 0) + ' L', moeda(gastoComb), custoKm ? 'R$ ' + fmtDec(custoKm, 2) + '/km' : 'N/D']);
}

// Postos utilizados hoje -- idem, sem corte de Top N.
const postosOrdenados = postos.slice().sort((a, b) => (b.total_litros || 0) - (a.total_litros || 0));
let rowsPostos = '';
for (const p of postosOrdenados) {
  const desvio = parseFloat(p.desvio_anp || 0);
  const desvioStr = (desvio > 0 ? '+' : '') + fmtDec(desvio, 1) + '%';
  const desvioCor = desvio <= 0 ? VERDE_ESC : ALERTA;
  rowsPostos += '<tr>'
    + '<td style="padding:9px 16px;font-weight:700;color:' + GRAFITE + ';font-size:12px;border-bottom:1px solid ' + LINHA + ';font-family:' + F_CORPO + '">' + (p.posto || 'Posto') + '</td>'
    + '<td style="padding:9px 16px;color:' + CINZA + ';font-size:12px;border-bottom:1px solid ' + LINHA + '">' + cleanCityUf(p.cidade, p.uf) + '</td>'
    + '<td style="padding:9px 16px;color:' + CINZA + ';font-size:12px;border-bottom:1px solid ' + LINHA + '">' + (p.combustivel || 'N/D') + '</td>'
    + '<td style="padding:9px 16px;text-align:right;color:' + CINZA + ';font-size:12px;border-bottom:1px solid ' + LINHA + ';font-variant-numeric:tabular-nums">' + numBr(p.total_litros, 0) + ' L</td>'
    + '<td style="padding:9px 16px;text-align:right;font-weight:700;color:' + GRAFITE + ';font-size:12px;border-bottom:1px solid ' + LINHA + ';font-variant-numeric:tabular-nums">' + moeda(p.total_gasto) + '</td>'
    + '<td style="padding:9px 16px;text-align:center;font-weight:700;color:' + desvioCor + ';font-size:12px;border-bottom:1px solid ' + LINHA + ';font-variant-numeric:tabular-nums">' + desvioStr + '</td>'
    + '</tr>';
}

// Faixa de contorno topografico -- identica ao semanal.
function faixaTopografica(altura, corLinha) {
  let paths = '';
  const alturas = [0.30, 0.45, 0.58, 0.70, 0.80, 0.88];
  const opacidades = [0.55, 0.42, 0.32, 0.24, 0.16, 0.10];
  for (let i = 0; i < alturas.length; i++) {
    const y = Math.round(altura * alturas[i]);
    const amp = 10 - i;
    paths += '<path d="M-10 ' + y + ' Q 90 ' + (y - amp) + ' 190 ' + y + ' T 390 ' + y
      + ' T 590 ' + y + ' T 790 ' + y + '" fill="none" stroke="' + corLinha + '" '
      + 'stroke-opacity="' + opacidades[i] + '" stroke-width="1.6"/>';
  }
  return 'data:image/svg+xml;base64,' + Buffer.from(
    '<svg xmlns="http://www.w3.org/2000/svg" width="760" height="' + altura + '" preserveAspectRatio="none">' + paths + '</svg>'
  ).toString('base64');
}
const contornoTopo = faixaTopografica(56, VERDE);

// Aviso de desvio ANP -- so aparece se pagou 3%+ acima da media nacional no
// dia (limiar mais alto que o semanal, ja que 1 dia tem mais ruido/outlier
// de posto isolado do que uma semana inteira). Puramente informativo.
const avisoAnp = desvioAnp > 3 ? (
  '<tr><td style="padding:16px 32px 0">'
  + '<div style="background:#FDF1F0;border:1px solid #F0D4D1;border-radius:6px;padding:12px 16px;font-size:12.5px;color:' + GRAFITE + ';font-family:' + F_CORPO + '">'
  + 'Preço médio pago hoje ficou <strong>' + fmtDec(desvioAnp, 1) + '% acima</strong> da referência ANP do dia.'
  + '</div></td></tr>'
) : '';

// --- Documento ----------------------------------------------------------
const html = '<!DOCTYPE html><html lang="pt-BR"><head><meta charset="UTF-8">'
+ '<meta name="viewport" content="width=device-width,initial-scale=1.0">'
+ '<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@600;700;800&family=IBM+Plex+Sans:wght@400;500;600&display=swap" rel="stylesheet">'
+ '</head><body style="margin:0;padding:0;background:' + FUNDO + ';font-family:' + F_CORPO + '">'

+ '<table width="100%" cellpadding="0" cellspacing="0" style="background:' + FUNDO + ';padding:28px 0">'
+ '<tr><td align="center">'
+ '<table width="680" cellpadding="0" cellspacing="0" style="max-width:680px;width:100%;'
+ 'background:' + BRANCO + ';border:1px solid ' + LINHA + ';border-radius:10px">'

+ '<tr><td style="background:' + FUNDO + ';border-radius:10px 10px 0 0;padding:0">'
+ '<img src="' + contornoTopo + '" width="680" height="56" style="display:block;width:100%;height:56px" alt="">'
+ '</td></tr>'
+ '<tr><td style="padding:18px 28px 16px">'
+ '<table width="100%" cellpadding="0" cellspacing="0"><tr>'
+ '<td valign="middle">'
+ '<img src="cid:logo_truckpag" height="24" style="display:block;height:24px;width:auto" alt="TruckPag">'
+ '<div style="font-size:10.5px;font-weight:700;text-transform:uppercase;letter-spacing:0.08em;color:' + CINZA + ';margin-top:10px;font-family:' + F_CORPO + '">Torre de Controle · Combustível diário</div>'
+ '<div style="font-size:19px;font-weight:800;color:' + GRAFITE + ';margin-top:3px;font-family:' + F_DISPLAY + '">' + (d.filial_nome || '—') + '</div>'
+ '</td>'
+ '<td valign="middle" align="right">'
+ '<div style="font-size:10.5px;font-weight:700;text-transform:uppercase;letter-spacing:0.08em;color:' + CINZA + ';font-family:' + F_CORPO + '">Dia</div>'
+ '<div style="font-size:13px;color:' + GRAFITE + ';margin-top:6px;font-family:' + F_CORPO + '">' + per.dataRef + '</div>'
+ '</td>'
+ '</tr></table></td></tr>'
+ '<tr><td style="border-bottom:1px solid ' + LINHA + '"></td></tr>'

+ '<tr><td style="padding:20px 28px 0">'
+ '<table width="100%" cellpadding="0" cellspacing="0" style="border:1px solid ' + LINHA + ';border-radius:8px;overflow:hidden">'
+ '<tr>' + th('Indicador') + th('Hoje', 'right') + th('Dia anterior', 'right') + th('Variação', 'right') + '</tr>'
+ linhaKpi('Gasto com combustível', kpiGasto)
+ linhaKpi('Volume abastecido (litros)', kpiLitros)
+ linhaKpi('Preço médio pago por litro', kpiPreco)
+ linhaKpi('Custo por km', kpiCustoKm)
+ linhaKpi('Veículos abastecidos', kpiVeic)
+ '</table></td></tr>'

+ avisoAnp

+ (frotaOrdenada.length > 0 ? (
  faixaSecao('Veículos abastecidos hoje')
  + '<tr><td style="padding:0 28px"><table width="100%" cellpadding="0" cellspacing="0" style="border:1px solid ' + LINHA + ';border-top:none;border-radius:0 0 6px 6px">'
  + '<tr>' + th('Placa') + th('Categoria') + th('Combustível') + th('Litros', 'right') + th('Gasto', 'right') + th('Custo/km', 'right') + '</tr>'
  + rowsFrota + '</table></td></tr>'
) : '')

+ (postosOrdenados.length > 0 ? (
  faixaSecao('Postos utilizados hoje')
  + '<tr><td style="padding:0 28px"><table width="100%" cellpadding="0" cellspacing="0" style="border:1px solid ' + LINHA + ';border-top:none;border-radius:0 0 6px 6px">'
  + '<tr>' + th('Posto') + th('Cidade / UF') + th('Combustível') + th('Volume', 'right') + th('Total gasto', 'right') + th('vs. ANP', 'center') + '</tr>'
  + rowsPostos + '</table></td></tr>'
) : '')

+ '<tr><td style="padding:18px 28px 0">'
+ '<div style="font-size:11.5px;color:' + CINZA + ';font-family:' + F_CORPO + '">Comparativo por grupo de veículo vs. referência da frota e extrato em CSV: relatório semanal.</div>'
+ '</td></tr>'

+ '<tr><td style="padding:22px 28px;background:' + AZUL_GRITSCH + ';border-radius:0 0 10px 10px;margin-top:20px">'
+ '<table width="100%" cellpadding="0" cellspacing="0"><tr>'
+ '<td valign="middle">'
+ '<img src="' + GRITSCH_LOGO_BRANCA + '" width="100" style="display:block;width:100px;height:auto" alt="Gritsch">'
+ '</td>'
+ '<td valign="middle" align="right" style="font-size:10.5px;color:' + BRANCO + ';line-height:1.6;font-family:' + F_CORPO + '">'
+ 'Relatório automático da Torre de Controle · diário<br>'
+ 'Dados fornecidos pela TruckPag<br>'
+ 'torredecontrole@gritsch.com.br'
+ '</td>'
+ '</tr></table></td></tr>'

+ '</table></td></tr></table></body></html>';

return {
  json: {
    htmlEmail: html,
    emailFinal,
    ccFinal,
    filial_nome: d.filial_nome,
  },
  binary: {
    logo_truckpag: {
      data: TRUCKPAG_LOGO_B64,
      mimeType: 'image/png',
      fileName: 'truckpag-logo.png',
    },
  },
};
