# 🎁 Lista de Presentes

Wishlist de aniversário funcionando como mini loja virtual. Frontend estático (HTML + CSS + JS puro, ES Modules) com Supabase como backend (Postgres + Auth + Storage + RLS).

## Escopo desta versão

Esta é uma versão **enxuta e funcional**, não o mini-e-commerce completo de 50 seções que pode ter sido especificado inicialmente. Cortes deliberados:
- Categorias e variações são campos simples no produto (texto livre / array), não tabelas relacionais — não há volume que justifique isso aqui.
- Expiração de reserva é checada na hora de tentar reservar de novo (dentro da própria RPC), sem job de limpeza nem pg_cron.
- 3 páginas (`index.html`, `login.html`, `admin.html`), sem `produto.html`/`cadastro.html` separados — detalhe do produto abre em modal, cadastro é modal no admin.
- Uma imagem por produto, sem galeria.

O que **não** foi cortado: Supabase Auth de verdade, RLS correta, RPC atômica com lock para evitar dupla reserva, produtos 100% vindos do banco (zero mock no HTML).

Se este projeto crescer (mais gente usando, categorias reaproveitadas entre eventos, etc.), o schema aguenta — o que muda é só a UI.

---

## Passo a passo de configuração

### 1. Criar projeto no Supabase
Acesse [supabase.com](https://supabase.com), crie uma conta e um novo projeto.

### 2. Rodar o `supabase.sql`
No painel do Supabase, vá em **SQL Editor** → **New query**, cole todo o conteúdo de `supabase.sql` e execute.

Isso cria as tabelas (`products`, `reservations`, `admin_users`, `site_settings`), os enums, as RPCs (`create_reservation`, `confirm_purchase`, `cancel_reservation`), as políticas de RLS e insere 6 produtos de exemplo.

**Antes de usar em produção**, remova os dados de exemplo:
```sql
delete from products where slug in (
  'controle-xbox','headset-gamer','tenis-nike','camiseta-basica','mouse-sem-fio','teclado-mecanico'
);
```

### 3. Criar um usuário administrador
No painel do Supabase: **Authentication** → **Users** → **Add user**. Defina um email e senha — será o login do painel admin.

### 4. Autorizar esse usuário como admin
Copie o **UUID** do usuário criado (coluna `UID` na lista de usuários) e rode no SQL Editor:
```sql
insert into admin_users (user_id) values ('COLE_O_UUID_AQUI');
```
Sem isso, o login funciona mas o painel bloqueia qualquer ação administrativa (a RPC de confirmar/cancelar compra checa `is_admin()`).

### 5. Criar o bucket de imagens
**Storage** → **New bucket** → nome exatamente `product-images` → marque **Public bucket**.

Depois, em **Storage** → **Policies**, adicione uma policy permitindo `INSERT` para usuários autenticados nesse bucket (o upload é feito pelo admin logado):
```sql
create policy "admin_upload_product_images"
on storage.objects for insert
to authenticated
with check (bucket_id = 'product-images');
```

### 6. Configurar as credenciais no projeto
Abra `js/supabase.js` e substitua:
```js
const SUPABASE_URL = 'COLE_AQUI_SUA_SUPABASE_URL';
const SUPABASE_ANON_KEY = 'COLE_AQUI_SUA_SUPABASE_ANON_KEY';
```
Os dois valores estão em **Project Settings** → **API** no painel do Supabase.

⚠️ Use sempre a **anon key** (pública, feita para o frontend). **Nunca** use a `service_role key` aqui — ela dá acesso total ao banco ignorando RLS.

### 7. Testar localmente
Como o projeto usa ES Modules, não pode abrir o `index.html` direto no navegador (`file://`) — precisa de um servidor local. Exemplos:
```bash
# Python
python3 -m http.server 8000

# Node (npx)
npx serve .
```
Acesse `http://localhost:8000`.

### 8. Publicar na Vercel
- Suba o projeto para um repositório no GitHub.
- Em [vercel.com](https://vercel.com), importe o repositório.
- Como é um projeto estático (sem build), o Vercel serve os arquivos diretamente — não precisa configurar build command.
- Depois do deploy, acesse `/login.html` para entrar no painel administrativo.

---

## Estrutura de arquivos

```
wishlist/
├── index.html          → catálogo público
├── login.html          → login do admin
├── admin.html          → painel administrativo
├── css/style.css        → estilo único
├── js/
│   ├── supabase.js      → configuração do cliente (credenciais aqui)
│   ├── auth.js          → login / logout / proteção de rota
│   ├── utils.js         → toasts, confirmações, formatação
│   ├── site.js          → lógica do catálogo público
│   ├── login.js         → lógica da página de login
│   └── admin.js         → lógica do painel (produtos, reservas, config)
└── supabase.sql          → schema completo do banco
```

## Fluxo de reserva

```
DISPONÍVEL → (visitante reserva) → RESERVADO → (admin confirma) → COMPRADO
                                       ↓
                          (admin cancela ou 24h passam sem confirmação)
                                       ↓
                                 DISPONÍVEL de novo
```

A reserva é feita pela RPC `create_reservation`, que usa `SELECT ... FOR UPDATE` para travar a linha do produto durante a checagem — isso impede que duas pessoas reservem o mesmo presente ao clicar quase ao mesmo tempo.
