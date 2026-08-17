# Controle de Recebíveis — instruções do projeto

Sistema web de **contas a receber** feito pelo Bruno (Silvaston/Bride).
Arquivo único: `index.html`. Sem build, sem dependências locais. Banco no Supabase.

Usado por **duas empresas com bancos totalmente separados**:
o cliente dele (**Abou Mazen**) e o **atacado dele mesmo**.

---

## ⚠️ ANTES DE PUBLICAR: rode os testes. Sempre.

```bash
./testar.sh
```

23 verificações: o JS compila, todas as funcionalidades continuam presentes, nenhuma chave
secreta escapou, os dois bancos estão de pé e trancados, os dois leitores de PDF ainda
funcionam, e as 34 telas abrem sem erro de JavaScript.

**Só publique se ele imprimir "PODE PUBLICAR".** Se falhar, não publique — investigue.
Isso existe porque, sem essa rede, quatro bugs chegaram ao Bruno em produção: um botão que
colidiu com outro, uma referência zerada antes do uso, um banco que voltava ao anterior e o
nome de uma empresa vazando na outra. Todos seriam pegos aqui.

Testes ficam em `testes/`. Se não existirem, extraia com `tar xzf testes.tgz`.

## Como publicar

O site é servido pelo **GitHub Pages** a partir da branch `main`, pasta raiz:
**https://brunosilvaston.github.io/recebiveis/**

```bash
./testar.sh && git add -A && git commit -m "descreva a mudança" && git push
```

Propaga em 1–2 minutos. Depois **avise o Bruno para recarregar com ⌘+Shift+R** — o navegador
guarda cache e ele já achou que não tinha funcionado por causa disso.

Confirme por fora que subiu:

```bash
wc -c index.html
curl -s "https://raw.githubusercontent.com/brunosilvaston/recebiveis/main/index.html?v=$RANDOM" | wc -c
curl -s -L "https://brunosilvaston.github.io/recebiveis/?v=$RANDOM" | wc -c
```

Os três números têm que bater. Se o site mostrar o tamanho antigo, é propagação — espere 30 s.

Se aparecer `cannot lock ref` ou `index.lock`: `rm -f .git/*.lock` e repita.

---

## Os dois bancos — qual é qual

| | **ABOU MAZEN** | **MEU ATACADO** (Bruno) |
|---|---|---|
| Projeto Supabase | `uoexrxgtaejwyftnxvhc` | `svyegvbggugfjgnhhorx` |
| **Conta Supabase** | **silvastonb@gmail.com** | **brideoficial01@gmail.com** |
| Organização | `brunosilvaston` | `recebiveis-atacado` |
| Região | São Paulo (sa-east-1) | São Paulo (sa-east-1) |
| Usuário de login | `abou` | `silvaston` |
| id no código | `mazen` | `atacado` |

**Se um pausar, entrar na conta certa** — é o erro mais fácil de cometer. O Bruno também tem
uma organização vazia chamada "Silvaston"; se a lista de projetos aparecer vazia, é org errada.

As chaves ficam no array `EMPRESAS`, no topo do `<script>`. São **publishable / anônimas —
públicas por natureza**, feitas para ficar no front-end. A proteção real são duas: **RLS**
(só usuário autenticado lê ou grava) e **cadastro público desligado** no painel.
**Nunca** colocar chave `service_role` neste arquivo — o `testar.sh` falha se encontrar.

Para acrescentar uma terceira empresa, basta somar um item no array `EMPRESAS`.

### Tabelas
`clientes` · `pedidos` · `itens` · `parcelas` · `recebimentos` · `config` + view `v_a_receber`.
Storage: bucket público `comprovantes`.

IDs determinísticos (importante para o upsert não duplicar):
item → `pedidoId-seq` · parcela → `pedidoId-n` (n começa em 1) · recebimento → `parcelaId-seq`

---

## Arquitetura

- **`index.html`** — a aplicação inteira: HTML, CSS e JS num só arquivo. É intencional: o Bruno
  precisa poder abrir o arquivo direto no navegador, sem servidor.
- **Supabase** por `fetch` direto na REST (PostgREST) e no GoTrue — **não usa supabase-js**,
  para não depender de CDN.
- **localStorage** é cache local, separado por empresa (`recebiveis_<emp>`, `sb_cfg_<emp>`,
  `sb_sessao_<emp>`, `sb_senha_ok_<emp>` — ver `ajustaKEY()`). A gravação no banco é
  **incremental por diff**: o espelho `ESPELHO` guarda o JSON de cada entidade já enviada e só
  o que mudou sobe. Debounce 1,2 s, retry 8 s, timeout 20 s (auth) / 30 s (dados).
- **Valores monetários sempre em centavos (inteiros)**. Nunca float para dinheiro.
  `r2c()` reais→centavos, `c2r()` formata.
- **Datas em ISO** (`aaaa-mm-dd`) internamente; `dbr()` exibe dd/mm/aaaa.
- **Vigia**: trigger no banco atualiza `config.versao` a cada alteração; o cliente lê a cada
  20 s (`vigiar()`) e recarrega se mudou. **Não dispara** com sync pendente, modal aberto ou
  pedido em edição — para não atropelar quem está digitando.

### Login
**Por nome de usuário, não por e-mail.** `paraEmail()` completa o que o usuário digita com
`@recebiveis.sistema` quando não tem "@"; `paraNome()` faz o contrário para exibir. Quem tem
e-mail real digita o e-mail e funciona igual.

**A empresa é descoberta pelo usuário**: o login tenta cada banco do array `EMPRESAS` e usa o
que aceitar. A tela **não mostra** as empresas — foi pedido do Bruno, para o Abou não saber que
existe outra. Cuidado: **o mesmo e-mail cadastrado nos dois bancos** faz o usuário cair no
primeiro que aceitar, possivelmente na empresa errada.

Senha provisória criada pelo dono → `avisarSenha()` pede troca no primeiro acesso →
`🔒 Trocar minha senha` no menu. Existe também convite por e-mail (`tokenDaURL` lê
`#access_token`) e "esqueci minha senha", que só funcionam para usuários com e-mail real.

### Importação de PDF
`parse()` detecta o formato e despacha:
- **`parsePedidoOK()`** — pedido do PedidoOK. Linhas remontadas por Y, colunas por gap de X
  (>6); item = linha `Código: XXX` + 3 últimos números; total = último valor após
  "VALOR TOTAL DO PEDIDO". O campo CONDIÇÃO DE PAGAMENTO do PDF **não** é usado.
- **`parseUpSeller()`** — Romaneio do UpSeller (vendas do atacado). Detecta por "UpSeller",
  "Romaneio" ou "print-packing-slip". Pega nº (`#0804`), data do "Hora do Pago", nome, CNPJ/CPF
  (vem sem pontuação — o parser formata), CEP, endereço, itens (`DESCRIÇÃO x QTD UNIT TOTAL`
  com o SKU 1-2 linhas abaixo), Total (não o Subtotal), desconto e frete.
  **Pegadinha:** o número do item aparece colado no fim da descrição ("RESPIRA1") porque fica
  em coluna separada. O parser remove comparando com a posição esperada do item — não corte
  dígitos do fim às cegas, isso estragaria "CHALEIRA 3L".
  Romaneio vem pago: sugere **à vista na data do pedido** e avisa para dar baixa.

PDF **escaneado** (imagem) não funciona — não tem texto dentro.

---

## Regras de negócio que não podem quebrar

1. **Soma das parcelas × total do pedido** — o sistema avisa quando difere, mas nunca deve
   silenciosamente "consertar" um valor que o usuário digitou.
2. **Editar pedido preserva pagamentos** por posição da parcela (1ª, 2ª…). Se a edição reduzir
   o número de parcelas e isso for apagar recebimentos, **confirmar antes**.
3. **"Total a Receber" e "Vencido" são posição de hoje** e não respeitam o filtro de período da
   Visão Geral. Deliberado: filtrar o "Vencido" faria o número mais crítico mostrar menos do
   que a realidade. Na aba Clientes, "Saldo devedor" também continua total.
4. **Pagamento parcial** é normal: `saldoDe(parcela) = valor − soma dos pagos`.
5. **Estorno** apaga o lançamento de recebimento, nunca "zera" a parcela por cima.
6. Número de pedido é **único** no banco (`ux_pedidos_num`). Avisar antes de duplicar.
7. **O nome da empresa vem só da config daquele banco.** Nunca herdar do estado anterior —
   isso fazia o nome de uma empresa aparecer na outra.

---

## Estilo de trabalho com o Bruno

- Ele **não é programador**. Explicar em português claro, sem jargão. Quando precisar que ele
  faça algo num painel, dar **passo a passo clique a clique**, com **link direto** e dizendo o
  que ele vai ver na tela. Ele usa Mac (⌘). Já pediu: "fala comigo como se eu fosse leigo".
- **Sempre diga qual arquivo e onde** — "publica" sem dizer o quê e o link já o irritou, com
  razão.
- **Um arquivo por passo**, rotulado ("SQL 1 de 2"). Vários anexos juntos confundem.
- **Nunca** fazer login na conta dele, digitar senha dele, receber token/PAT, nem apagar
  projeto ou dados por ele. Essas ações são dele — explicar e mandar o caminho.
- **Sempre conferir por fora se deu certo** (curl no site, curl no banco) em vez de confiar no
  "já fiz". Ele já disse "rodei" com o SQL não rodado, duas vezes.
- Ser direto sobre o que não funciona e por quê. Ele prefere o problema nomeado a um contorno
  mal explicado. E **admitir erro próprio rápido** — vários bugs aqui foram meus.

### Armadilhas técnicas já pagas
- `document.body.textContent` **inclui o texto dentro de `<script>`** — não usar para asserção.
- `toLocaleString('pt-BR',{style:'currency'})` usa **espaço não-quebrável** (U+00A0) entre "R$"
  e o número. Normalizar antes de comparar em teste.
- Mudar só o `#` da URL **não recarrega a página** — para testar link de convite, navegar com
  query diferente ou `about:blank` antes.
- Reiniciar o banco falso entre execuções: estado residual gera falso negativo.
- O banco falso precisa de **CORS liberado incluindo PUT** e responder `OPTIONS` com 204.
- Não usar `pkill -f <padrão>` se o padrão aparece no próprio comando (mata o shell);
  usar `fuser -k -n tcp <porta>`.

---

## Operação do Supabase (para avisar o Bruno quando precisar)

Painéis:
- Mazen: https://supabase.com/dashboard/project/uoexrxgtaejwyftnxvhc
- Atacado: https://supabase.com/dashboard/project/svyegvbggugfjgnhhorx

- **Plano free pausa o projeto após 7 dias sem uso.** Sintoma: o subdomínio
  `<projeto>.supabase.co` **para de resolver no DNS** e todo request morre em timeout.
  Correção: o Bruno abre o painel e clica em **Restore**. Nada é perdido. Depois do restore o
  banco fica ~2 min instável (tabelas dão timeout, Storage responde `544`) — esperar e re-testar.
- **Free não tem backup automático.** O sistema tem "↓ Backup (.json)" no menu; orientar uso
  semanal **dos dois bancos**. Pro (US$ 25/mês) nunca pausa e faz backup diário.
- **"Allow new users to sign up" tem que ficar DESLIGADO** nos dois (Auth → Sign In /
  Providers → User Signups). É isso que impede qualquer pessoa que ache o link de criar conta
  e ver os dados. O `testar.sh` verifica isso nos dois bancos.
- Criar acesso novo: Authentication → Users → Add user → Create new user, e-mail no formato
  `nome@recebiveis.sistema`, marcando **Auto Confirm User**. O painel exige formato de e-mail;
  o domínio é inventado e não precisa existir.
- SQL: alterações de schema devem ser **idempotentes** (`add column if not exists`,
  `create or replace`) porque ele roda os scripts mais de uma vez. **`create or replace view`
  não aceita mudança de nome ou ordem de coluna** — usar `drop view if exists` antes.

---

## Funcionalidades já entregues

Importação de PDF do PedidoOK e do Romaneio UpSeller · produtos editáveis com recálculo cruzado
e desconto em R$ · edição de pedido lançado preservando pagamentos · parcelas com datas e
valores livres, presets, adicionar/remover, "distribuir o que falta" · baixa parcial com forma
de pagamento e comprovante no Storage · histórico de pagamentos por cliente com estorno
individual · selo "✓ Pago em dd/mm/aaaa" e linha verde nas listas · cadastro completo de cliente
(e-mail, IE, contato, endereço de entrega, bairro, CEP, transportadora, prazo) · filtro de
período na Visão Geral com 5 indicadores e painel de entradas de caixa · filtro de período e
busca nas abas Pedidos e Clientes · duas empresas com bancos separados · exportação .xlsx ·
extrato imprimível por cliente.

## Fora de escopo (não implementar sem pedir)

Juros e multa por atraso · cobrança automática por WhatsApp · bloqueio por limite de crédito ·
guardar o PDF do pedido junto do registro · visão somando as duas empresas.
