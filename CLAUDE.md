# Controle de Recebíveis — instruções do projeto

Sistema web de **contas a receber** feito pelo Bruno (Silvaston/Bride) para o **Abou Mazen**.
Arquivo único: `index.html`. Sem build, sem dependências locais. Banco no Supabase.

## Como publicar (o motivo deste repositório)

O site é servido pelo **GitHub Pages** a partir da branch `main`, pasta raiz:
**https://brunosilvaston.github.io/recebiveis/**

Para publicar uma alteração, basta commitar e dar push no `index.html`. O Pages propaga em
1–2 minutos. Sempre avisar o Bruno para recarregar com **⌘+Shift+R** (o navegador guarda cache).

```bash
git add index.html && git commit -m "descreva a mudança" && git push
```

Depois de publicar, **confirmar que subiu**:

```bash
curl -s "https://raw.githubusercontent.com/brunosilvaston/recebiveis/main/index.html?v=$RANDOM" | wc -c
curl -s -L "https://brunosilvaston.github.io/recebiveis/?v=$RANDOM" | wc -c
```

Os dois números têm que bater com `wc -c index.html`. Se o site ainda mostrar o tamanho antigo,
é propagação — esperar 30 s e repetir.

## Arquitetura

- **`index.html`** — a aplicação inteira: HTML, CSS e JS num só arquivo. É intencional: o Bruno
  precisa poder abrir o arquivo direto no navegador, sem servidor.
- **Supabase** (Postgres + Auth + Storage) como banco. O cliente fala por `fetch` direto na API
  REST (PostgREST) e no GoTrue — **não usa a biblioteca supabase-js**, para não depender de CDN.
- **localStorage** é cache local. A gravação no banco é **incremental por diff**: um espelho
  (`ESPELHO`) guarda o JSON de cada entidade já enviada e só o que mudou sobe.
- **Valores monetários sempre em centavos (inteiros)**. Nunca usar float para dinheiro.
  `r2c()` converte reais→centavos, `c2r()` formata para exibição.
- **Datas em ISO** (`aaaa-mm-dd`) internamente; `dbr()` exibe em dd/mm/aaaa.

### Conexão com o banco (embutida no arquivo)

```
URL:   https://uoexrxgtaejwyftnxvhc.supabase.co
Chave: sb_publishable_Fx5jb0a1jQE6a8Ny1Q6Vxg_756uKwjf
```

A chave é **publishable / anônima — pública por natureza**, feita para ficar no front-end. Não é
segredo e não precisa ser escondida. A proteção real são duas: **RLS** (só usuário autenticado lê
ou grava) e **cadastro público desligado** no painel do Supabase. Nunca colocar a chave
`service_role` neste arquivo.

### Tabelas

`clientes` · `pedidos` · `itens` · `parcelas` · `recebimentos` · `config` + view `v_a_receber`.
Storage: bucket público `comprovantes`.

IDs determinísticos (importante para o upsert não duplicar):
- item → `pedidoId-seq`
- parcela → `pedidoId-n` (n começa em 1)
- recebimento → `parcelaId-seq`

### Login

Login **por nome de usuário**, não por e-mail. `paraEmail()` completa o que o usuário digita com
`@recebiveis.sistema` quando não tem "@". `paraNome()` faz o contrário para exibir. Quem tem
e-mail real digita o e-mail e funciona igual.

Usuário do Abou: `abou@recebiveis.sistema`. Existe também fluxo de convite por e-mail
(`tokenDaURL` lê `#access_token` da URL) e "esqueci minha senha".

### Atualização automática entre computadores

Um trigger no banco atualiza `config.versao` a cada alteração. O cliente lê essa linha a cada
20 s (`vigiar()`) e recarrega tudo se mudou. **Não dispara** quando há sync pendente, modal aberto
ou pedido em edição — para não atropelar quem está digitando.

## Como testar antes de publicar

Não existe suíte no repositório, mas **é obrigatório testar** — este sistema controla dinheiro de
verdade. O mínimo, sempre:

```bash
# 1) o JS parseia?
node -e "
const h=require('fs').readFileSync('index.html','utf8');
const c=h.match(/<script>([\s\S]*)<\/script>\s*<\/body>/)[1];
try{ new Function(c.replace(/\bawait /g,'')); console.log('JS OK'); }
catch(e){ console.log('ERRO:',e.message); process.exit(1); }
"
```

Para mudanças de comportamento, subir um **mock da API do Supabase** (servidor HTTP simples que
responde `/auth/v1/token`, `/auth/v1/user`, `/rest/v1/<tabela>`) e dirigir a página com
**Playwright**, conferindo os valores na mão. Cuidados aprendidos:

- O mock precisa de **CORS liberado incluindo PUT** e responder `OPTIONS` com 204.
- `toLocaleString('pt-BR',{style:'currency'})` usa **espaço não-quebrável** (U+00A0) entre "R$" e
  o número. Normalizar com `.replace(/ /g,' ')` antes de comparar strings em teste.
- `document.body.textContent` **inclui o texto dentro de `<script>`** — não usar para asserção,
  senão o próprio código-fonte casa com o regex.
- Mudar só o `#` da URL **não recarrega a página** no Playwright; para testar link de convite,
  navegar com query diferente ou `about:blank` antes.
- Reiniciar o mock entre execuções: estado residual gera falsos negativos.

## Regras de negócio que não podem quebrar

1. **Soma das parcelas × total do pedido** — o sistema avisa quando difere, mas nunca deve
   silenciosamente "consertar" um valor que o usuário digitou.
2. **Editar pedido preserva pagamentos** por posição da parcela (1ª, 2ª…). Se a edição reduzir o
   número de parcelas e isso for apagar recebimentos, **confirmar com o usuário antes**.
3. **"Total a Receber" e "Vencido" são posição de hoje** e não respeitam o filtro de período da
   Visão Geral. Isso é deliberado: filtrar o "Vencido" faria o número mais crítico do sistema
   mostrar menos do que a realidade.
4. **Pagamento parcial** é normal: `saldoDe(parcela) = valor − soma dos pagos`.
5. **Estorno** apaga o lançamento de recebimento, nunca "zera" a parcela por cima.
6. Número de pedido é **único** no banco (`ux_pedidos_num`). Avisar antes de tentar duplicar.

## Estilo de trabalho com o Bruno

- Ele **não é programador**. Explicar em português claro, sem jargão. Quando precisar que ele faça
  algo num painel, dar **passo a passo clique a clique**, com link direto e dizendo o que ele vai
  ver na tela. Ele usa Mac (⌘).
- **Nunca** fazer login na conta dele, digitar senha dele, nem apagar projeto/dados por ele.
  Essas ações são dele — explicar e mandar o caminho.
- **Sempre conferir por fora se deu certo** (curl no site, curl no banco) em vez de confiar no
  "já fiz". Isso já evitou retrabalho várias vezes.
- Ser direto sobre o que não funciona e por quê. Ele prefere o problema nomeado a um contorno mal
  explicado.

## Operação do Supabase (para avisar o Bruno quando precisar)

Painel: https://supabase.com/dashboard/project/uoexrxgtaejwyftnxvhc
(organização **brunosilvaston** — ele tem outra org vazia chamada "Silvaston"; se a lista de
projetos aparecer vazia, é org errada.)

- **Plano free pausa o projeto após 7 dias sem uso.** Sintoma: o subdomínio
  `uoexrxgtaejwyftnxvhc.supabase.co` **para de resolver no DNS** e todo request morre em timeout.
  Correção: o Bruno abre o painel e clica em **Restore**. Nada é perdido. Depois do restore o
  banco fica ~2 min instável (algumas tabelas dão timeout, Storage responde `544`) — esperar.
- **Free não tem backup automático.** O sistema tem "↓ Backup (.json)" no menu; orientar uso
  semanal. Plano Pro (US$ 25/mês) nunca pausa e faz backup diário.
- **"Allow new users to sign up" tem que ficar DESLIGADO** (Auth → Sign In / Providers → User
  Signups). É isso que impede qualquer pessoa que ache o link de criar conta e ver os dados.
- Criar acesso novo: Authentication → Users → Add user → Create new user, e-mail no formato
  `nome@recebiveis.sistema`, marcando **Auto Confirm User**.
- SQL: alterações de schema devem ser **idempotentes** (`add column if not exists`,
  `create or replace`) porque ele roda os scripts mais de uma vez.

## Funcionalidades já entregues

Importação do PDF do PedidoOK (arrastar) · produtos editáveis com desconto · edição de pedido
lançado · parcelas com datas e valores livres · baixa parcial com forma de pagamento e comprovante
· histórico de pagamentos por cliente com estorno individual · selo "✓ Pago em dd/mm/aaaa" ·
cadastro completo de cliente (e-mail, IE, endereço de entrega, transportadora) · filtro de período
na Visão Geral com painel de entradas de caixa · exportação .xlsx · extrato imprimível por cliente.

## Fora de escopo (não implementar sem pedir)

Juros e multa por atraso · cobrança automática por WhatsApp · bloqueio por limite de crédito ·
guardar o PDF do pedido junto do registro.
