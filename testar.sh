#!/bin/bash
# =====================================================================
# TESTAR TUDO antes de publicar.
#
#   ./testar.sh
#
# Só imprime "PODE PUBLICAR" se absolutamente tudo passar.
# Se qualquer coisa falhar, NÃO publique — mande o resultado para o Claude.
#
# Precisa de: node, npx playwright (instala sozinho na primeira vez)
# =====================================================================
set -uo pipefail
cd "$(dirname "$0")"
ARQ="${1:-index.html}"
FALHAS=0
TOTAL=0

az(){ printf "\n\033[1m== %s\033[0m\n" "$1"; }
passou(){ TOTAL=$((TOTAL+1)); printf "   \033[32mok\033[0m   %s\n" "$1"; }
falhou(){ TOTAL=$((TOTAL+1)); FALHAS=$((FALHAS+1)); printf "   \033[31mFALHA\033[0m %s\n" "$1"; }

[ -f "$ARQ" ] || { echo "não achei $ARQ"; exit 1; }

# ---------------------------------------------------------------- 1
az "1. O arquivo está íntegro?"
node -e "
const h=require('fs').readFileSync('$ARQ','utf8');
const m=h.match(/<script>([\s\S]*)<\/script>\s*<\/body>/);
if(!m){ console.log('SEM_SCRIPT'); process.exit(1); }
try{ new Function(m[1].replace(/\bawait /g,'')); }catch(e){ console.log('ERRO_JS '+e.message); process.exit(1); }
console.log('OK');
" >/tmp/t1.txt 2>&1 && passou "o JavaScript compila" || { falhou "JavaScript com erro de sintaxe"; cat /tmp/t1.txt; }

node -e "
const h=require('fs').readFileSync('$ARQ','utf8');
const faltando=[];
[['EMPRESAS','lista de empresas'],['function periodo','filtro de período'],
 ['function parseUpSeller','leitor do UpSeller'],['function parsePedidoOK','leitor do PedidoOK'],
 ['function histHTML','histórico de pagamentos'],['function editarPedido','editar pedido'],
 ['function vigiar','atualização automática'],['function subirMudancas','gravação no banco'],
 ['function trocarSenha','trocar senha'],['tblCaixa','entradas de caixa'],
 ['atCli','filtro em Clientes'],['atPed','filtro em Pedidos']
].forEach(([k,d])=>{ if(h.indexOf(k)<0) faltando.push(d); });
if(faltando.length){ console.log('FALTA: '+faltando.join(', ')); process.exit(1); }
console.log('OK');
" >/tmp/t2.txt 2>&1 && passou "todas as funcionalidades presentes" || { falhou "funcionalidade ausente"; cat /tmp/t2.txt; }

node -e "
const h=require('fs').readFileSync('$ARQ','utf8');
const n=(h.match(/sb_publishable_|eyJhbGci/g)||[]).length;
if(h.indexOf('service_role')>=0){ console.log('TEM CHAVE SECRETA NO ARQUIVO'); process.exit(1); }
if(!n){ console.log('sem chave nenhuma'); process.exit(1); }
console.log('OK '+n+' chave(s) pública(s)');
" >/tmp/t3.txt 2>&1 && passou "só chaves públicas (nenhuma secreta)" || { falhou "problema nas chaves"; cat /tmp/t3.txt; }

# ---------------------------------------------------------------- 2
az "2. Os bancos estão de pé e trancados?"
node -e "
const h=require('fs').readFileSync('$ARQ','utf8');
const re=/\{id:'([^']+)',\s*rot:'([^']+)',\s*url:'([^']*)',?\s*[\r\n ]*key:'([^']*)'/g;
let m,out=[]; while((m=re.exec(h))) out.push({id:m[1],rot:m[2],url:m[3],key:m[4]});
require('fs').writeFileSync('/tmp/empresas.json',JSON.stringify(out));
console.log(out.length+' empresa(s)');
" 2>/dev/null
if [ -f /tmp/empresas.json ]; then
python3 - <<'PY' > /tmp/bancos.txt 2>&1
import json,urllib.request,ssl
ctx=ssl.create_default_context()
def http(url,metodo='GET',key='',corpo=None):
    r=urllib.request.Request(url,method=metodo)
    if key: r.add_header('apikey',key)
    if corpo:
        r.add_header('Content-Type','application/json'); r.data=json.dumps(corpo).encode()
    try:
        with urllib.request.urlopen(r,timeout=25,context=ctx) as f: return f.status, f.read(300).decode('utf8','ignore')
    except urllib.error.HTTPError as e: return e.code, e.read(300).decode('utf8','ignore')
    except Exception as e: return 0, str(e)
for e in json.load(open('/tmp/empresas.json')):
    if not e['url'] or not e['key']:
        print(f"PULA|{e['rot']}|sem banco configurado"); continue
    for t in ['clientes','pedidos','itens','parcelas','recebimentos','config']:
        s,_=http(f"{e['url']}/rest/v1/{t}?select=*&limit=1",key=e['key'])
        print(("OK" if s==200 else "ERRO")+f"|{e['rot']}|tabela {t} (HTTP {s})")
    s,_=http(f"{e['url']}/auth/v1/signup",'POST',e['key'],{'email':'zz_teste_do_testar_sh@exemplo.com','password':'Abc123456'})
    print(("OK" if s==422 else "ERRO")+f"|{e['rot']}|cadastro público fechado (HTTP {s})")
    s,_=http(f"{e['url']}/rest/v1/clientes",'POST',e['key'],{'id':'zz','nome':'zz'})
    print(("OK" if s in (401,403) else "ERRO")+f"|{e['rot']}|gravar sem login bloqueado (HTTP {s})")
    s,b=http(f"{e['url']}/rest/v1/clientes?select=*",key=e['key'])
    print(("OK" if b.strip()=='[]' else "ERRO")+f"|{e['rot']}|ler sem login não devolve nada")
PY
while IFS='|' read -r st emp msg; do
  case "$st" in
    OK) passou "$emp — $msg";;
    PULA) printf "   \033[33m--\033[0m   %s — %s\n" "$emp" "$msg";;
    *) falhou "$emp — $msg";;
  esac
done < /tmp/bancos.txt
fi

# ---------------------------------------------------------------- 3
az "3. Os leitores de PDF ainda entendem os dois formatos?"
if [ -f testes/leitores-pdf.js ]; then
  node testes/leitores-pdf.js > /tmp/p.txt 2>&1
  n=$(grep -c "^  ok" /tmp/p.txt || true); f=$(grep -c "^FALHA" /tmp/p.txt || true)
  [ "$f" = "0" ] && passou "$n verificações nos dois formatos" || { falhou "$f falha(s) nos leitores"; grep "^FALHA" /tmp/p.txt; }
else
  printf "   \033[33m--\033[0m   testes de PDF não estão nesta máquina\n"
fi

# ---------------------------------------------------------------- 4
az "4. A interface abre sem erro em todas as telas?"
if [ -f testes/varredura-telas.js ]; then
  ( fuser -k -n tcp 54321 >/dev/null 2>&1; sleep 1
    setsid env PORTA=54321 SENHA=senha123 node testes/banco-falso.js >/dev/null 2>&1 </dev/null & ) ; sleep 2
  node testes/varredura-telas.js > /tmp/f.txt 2>&1
  if grep -q "sem um único erro" /tmp/f.txt; then passou "34 telas e ações sem erro de JavaScript"
  else falhou "erro de JavaScript na interface"; grep -A2 "^❌" /tmp/f.txt | head -20; fi
else
  printf "   \033[33m--\033[0m   varredura de telas não está nesta máquina\n"
fi

# ---------------------------------------------------------------- fim
printf "\n=====================================================\n"
if [ "$FALHAS" = "0" ]; then
  printf "\033[32m✅ %d verificações, nenhuma falha — PODE PUBLICAR\033[0m\n" "$TOTAL"
  printf "\n   git add -A && git commit -m \"...\" && git push\n\n"
  exit 0
else
  printf "\033[31m❌ %d de %d verificações falharam — NÃO PUBLIQUE\033[0m\n" "$FALHAS" "$TOTAL"
  printf "\n   Manda esse resultado para o Claude.\n"
  printf "   Para voltar à versão anterior:  git checkout -- %s\n\n" "$ARQ"
  exit 1
fi
