#!/bin/bash
# ==================================================================
#  PMESP MANAGER ULTIMATE V8.0 - SMTP GMAIL EDITION
#  Gestão de Usuários, Chamados, HWID e E-mail Real.
# ==================================================================

# --- ARQUIVOS DE DADOS ---
DB_PMESP="/etc/pmesp_users.json"
DB_CHAMADOS="/etc/pmesp_tickets.json"
CONFIG_SMTP="/etc/msmtprc"

# Garante arquivos básicos
if [ ! -f "$DB_PMESP" ]; then touch "$DB_PMESP"; chmod 666 "$DB_PMESP"; fi
if [ ! -f "$DB_CHAMADOS" ]; then touch "$DB_CHAMADOS"; chmod 666 "$DB_CHAMADOS"; fi

# --- CORES ---
COR_FUNDO='\033[1;44;37m' 
COR_RESET='\033[0m'
COR_VERDE='\033[1;32m'
COR_VERMELHO='\033[1;31m'
COR_AMARELO='\033[1;33m'
COR_AZUL='\033[1;34m'
COR_CIANO='\033[1;36m'
COR_ROXO='\033[1;35m'

# --- INSTALAÇÃO DE DEPENDÊNCIAS ---
install_deps() {
    clear
    echo -e "${COR_AMARELO}Instalando Dependências...${COR_RESET}"
    export DEBIAN_FRONTEND=noninteractive
    
    # Atualiza lista
    apt-get update -y >/dev/null 2>&1
    
    # Instala ferramentas básicas + msmtp (para e-mail) + jq (json)
    apt-get install bc screen nano net-tools lsof cron zip unzip jq msmtp msmtp-mta ca-certificates -y >/dev/null 2>&1
    
    echo -e "${COR_VERDE}Sistema Pronto! Pacotes de e-mail instalados.${COR_RESET}"
    sleep 2
}

# --- FUNÇÕES VISUAIS ---
barra() { echo -e "${COR_AZUL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COR_RESET}"; }

cabecalho() {
    clear
    echo -e "${COR_AZUL}╭━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╮${COR_RESET}"
    echo -e "${COR_AZUL}┃${COR_FUNDO}      PMESP MANAGER V8.0 - TÁTICO INTEGRADO     ${COR_RESET}${COR_AZUL}┃${COR_RESET}"
    echo -e "${COR_AZUL}╰━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╯${COR_RESET}"
}

# --- CONFIGURAÇÃO DO GMAIL (NOVA FUNÇÃO) ---
configurar_smtp() {
    cabecalho
    echo -e "${COR_ROXO}>>> CONFIGURAÇÃO DE SERVIDOR DE E-MAIL (GMAIL)${COR_RESET}"
    echo "Necessário ter a 'Senha de App' gerada no Google."
    echo ""
    
    read -p "Seu E-mail Gmail (Ex: pmesp@gmail.com): " email_adm
    read -p "Sua Senha de App (16 letras): " senha_app
    
    echo -e "\n${COR_AMARELO}Configurando o cliente SMTP...${COR_RESET}"
    
    # Cria o arquivo de configuração do msmtp
    cat <<EOF > "$CONFIG_SMTP"
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        gmail
host           smtp.gmail.com
port           587
from           $email_adm
user           $email_adm
password       $senha_app

account default : gmail
EOF

    # Permissão 600 é crucial para segurança (só root lê a senha)
    chmod 600 "$CONFIG_SMTP"
    
    echo -e "${COR_VERDE}Configuração salva em $CONFIG_SMTP!${COR_RESET}"
    echo -e "Enviando e-mail de teste para você mesmo..."
    
    # Teste de envio
    echo -e "Subject: Teste PMESP Manager\n\nO sistema de e-mail da VPS esta operante." | msmtp "$email_adm"
    
    if [ $? -eq 0 ]; then
        echo -e "${COR_VERDE}E-mail de teste enviado! Verifique sua caixa de entrada.${COR_RESET}"
    else
        echo -e "${COR_VERMELHO}Erro ao enviar. Verifique se a senha de app está correta.${COR_RESET}"
    fi
    read -p "Enter para voltar..."
}

# --- GESTÃO DE USUÁRIOS ---

criar_usuario() {
    cabecalho
    echo -e "${COR_VERDE}>>> NOVO CADASTRO${COR_RESET}"
    read -p "Matrícula (RE): " matricula
    read -p "Email do Policial: " email
    read -p "Login (Usuário): " usuario
    
    if id "$usuario" >/dev/null 2>&1; then
        echo -e "\n${COR_VERMELHO}ERRO: Usuário já existe!${COR_RESET}"; sleep 2; return
    fi
    
    read -p "Senha Provisória: " senha
    read -p "Validade (Dias): " dias
    read -p "Limite de Telas: " limite
    
    # Linux User
    useradd -M -s /bin/false "$usuario"
    echo "$usuario:$senha" | chpasswd
    
    # Validade
    data_final=$(date -d "+$dias days" +"%Y-%m-%d")
    chage -E "$data_final" "$usuario"
    
    # JSON Save
    jq -n --arg u "$usuario" --arg s "$senha" --arg d "$dias" --arg l "$limite" \
          --arg m "$matricula" --arg e "$email" --arg h "PENDENTE" \
          '{usuario: $u, senha: $s, dias: $d, limite: $l, matricula: $m, email: $e, hwid: $h}' \
          >> "$DB_PMESP"

    echo -e "${COR_VERDE}Usuário Criado!${COR_RESET}"
    read -p "Enter..."
}

atualizar_hwid() {
    cabecalho
    echo -e "${COR_AMARELO}>>> VINCULAR HWID${COR_RESET}"
    read -p "Usuário alvo: " user_alvo
    read -p "Novo HWID: " novo_hwid
    
    if ! grep -q "\"usuario\": \"$user_alvo\"" "$DB_PMESP"; then
        echo -e "${COR_VERMELHO}Usuário não encontrado!${COR_RESET}"; sleep 2; return
    fi

    # Lógica de atualização JSON segura
    linha=$(grep "\"usuario\": \"$user_alvo\"" "$DB_PMESP")
    # Pega dados antigos
    s=$(echo $linha | jq -r .senha); d=$(echo $linha | jq -r .dias)
    l=$(echo $linha | jq -r .limite); m=$(echo $linha | jq -r .matricula)
    e=$(echo $linha | jq -r .email)
    
    # Remove antigo
    grep -v "\"usuario\": \"$user_alvo\"" "$DB_PMESP" > "${DB_PMESP}.tmp" && mv "${DB_PMESP}.tmp" "$DB_PMESP"
    
    # Adiciona novo
    jq -n --arg u "$user_alvo" --arg s "$s" --arg d "$d" --arg l "$l" \
          --arg m "$m" --arg e "$e" --arg h "$novo_hwid" \
          '{usuario: $u, senha: $s, dias: $d, limite: $l, matricula: $m, email: $e, hwid: $h}' \
          >> "$DB_PMESP"
      
    echo -e "${COR_VERDE}HWID Atualizado.${COR_RESET}"; sleep 2
}

# --- SISTEMA DE CHAMADOS ---
novo_chamado() {
    cabecalho; echo -e "${COR_CIANO}>>> NOVO CHAMADO${COR_RESET}"
    ID=$((1000 + RANDOM % 8999)); DATA=$(date "+%d/%m/%Y %H:%M")
    read -p "Usuário: " user; read -p "Problema: " prob
    jq -n --arg i "$ID" --arg u "$user" --arg p "$prob" --arg s "ABERTO" --arg d "$DATA" \
       '{id: $i, usuario: $u, problema: $p, status: $s, data: $d}' >> "$DB_CHAMADOS"
    echo -e "${COR_VERDE}Chamado #$ID criado.${COR_RESET}"; sleep 2
}

gerenciar_chamados() {
    while true; do
        cabecalho
        printf "${COR_AZUL}%-6s | %-12s | %-10s | %-20s${COR_RESET}\n" "ID" "USER" "STATUS" "DESC"
        barra
        while read -r line; do
            i=$(echo "$line" | jq -r .id); u=$(echo "$line" | jq -r .usuario)
            p=$(echo "$line" | jq -r .problema); s=$(echo "$line" | jq -r .status)
            if [ "$s" == "ABERTO" ]; then C=$COR_VERMELHO; else C=$COR_VERDE; fi
            printf "%-6s | %-12s | ${C}%-10s${COR_RESET} | %-20s\n" "$i" "$u" "$s" "${p:0:20}..."
        done < "$DB_CHAMADOS"
        echo ""; echo "[1] Fechar Chamado | [2] Deletar Chamado | [0] Voltar"
        read -p "Op: " opc
        case $opc in
            1) read -p "ID: " id; tmp=$(mktemp)
               while read -l; do
                 cid=$(echo "$l" | jq -r .id)
                 if [ "$cid" == "$id" ]; then echo "$l" | jq '.status="ENCERRADO"' >> "$tmp"; else echo "$l" >> "$tmp"; fi
               done < "$DB_CHAMADOS"; mv "$tmp" "$DB_CHAMADOS" ;;
            2) read -p "ID: " id; grep -v "\"id\": \"$id\"" "$DB_CHAMADOS" > t.json && mv t.json "$DB_CHAMADOS" ;;
            0) return ;;
        esac
    done
}

# --- RECUPERAÇÃO DE SENHA (AGORA COM SMTP REAL) ---
recuperar_senha() {
    cabecalho
    echo -e "${COR_ROXO}>>> RESETAR SENHA E ENVIAR EMAIL${COR_RESET}"
    
    # Verifica se SMTP está configurado
    if [ ! -f "$CONFIG_SMTP" ]; then
        echo -e "${COR_VERMELHO}ERRO: Configure o SMTP (Opção 8) primeiro!${COR_RESET}"; sleep 3; return
    fi
    
    read -p "Usuário para reset: " user_alvo
    
    if ! grep -q "\"usuario\": \"$user_alvo\"" "$DB_PMESP"; then
        echo -e "${COR_VERMELHO}Usuário não existe.${COR_RESET}"; sleep 2; return
    fi
    
    linha=$(grep "\"usuario\": \"$user_alvo\"" "$DB_PMESP")
    email_dest=$(echo "$linha" | jq -r .email)
    
    if [ -z "$email_dest" ] || [ "$email_dest" == "null" ]; then
        echo -e "${COR_VERMELHO}Usuário sem e-mail cadastrado.${COR_RESET}"; sleep 2; return
    fi
    
    # Gera senha e atualiza sistema
    nova_senha=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
    echo "$user_alvo:$nova_senha" | chpasswd
    
    # Atualiza JSON
    grep -v "\"usuario\": \"$user_alvo\"" "$DB_PMESP" > "${DB_PMESP}.tmp" && mv "${DB_PMESP}.tmp" "$DB_PMESP"
    
    jq -n --arg u "$user_alvo" --arg s "$nova_senha" \
          --arg d "$(echo $linha | jq -r .dias)" --arg l "$(echo $linha | jq -r .limite)" \
          --arg m "$(echo $linha | jq -r .matricula)" --arg e "$email_dest" \
          --arg h "$(echo $linha | jq -r .hwid)" \
          '{usuario: $u, senha: $s, dias: $d, limite: $l, matricula: $m, email: $e, hwid: $h}' \
          >> "$DB_PMESP"
          
    echo -e "Enviando e-mail para ${COR_AMARELO}$email_dest${COR_RESET}..."
    
    # ENVIO REAL COM MSMTP
    (
        echo "To: $email_dest"
        echo "Subject: [PMESP] Nova Senha de Acesso"
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/plain; charset=utf-8"
        echo ""
        echo "==== SISTEMA INTEGRADO PMESP ===="
        echo ""
        echo "Solicitação de reset de senha processada."
        echo ""
        echo "Usuário: $user_alvo"
        echo "Nova Senha: $nova_senha"
        echo ""
        echo "Favor alterar sua senha assim que possível."
        echo "================================="
    ) | msmtp "$email_dest"
    
    if [ $? -eq 0 ]; then
        echo -e "${COR_VERDE}SUCESSO! E-mail enviado.${COR_RESET}"
    else
        echo -e "${COR_VERMELHO}FALHA NO ENVIO. Senha gerada: $nova_senha${COR_RESET}"
    fi
    read -p "Enter..."
}

# --- MENU ---
menu() {
    while true; do
        cabecalho
        echo -e "   ${COR_VERDE}[ GESTÃO ]${COR_RESET}"
        echo -e "${COR_AMARELO}[1]${COR_RESET} Criar Usuário"
        echo -e "${COR_AMARELO}[2]${COR_RESET} Remover Usuário"
        echo -e "${COR_AMARELO}[3]${COR_RESET} Vincular HWID"
        echo -e "${COR_AMARELO}[4]${COR_RESET} Resetar Senha (Email)"
        echo ""
        echo -e "   ${COR_VERDE}[ SUPORTE ]${COR_RESET}"
        echo -e "${COR_CIANO}[5]${COR_RESET} Abrir Chamado"
        echo -e "${COR_CIANO}[6]${COR_RESET} Gerenciar Chamados"
        echo ""
        echo -e "   ${COR_VERDE}[ SISTEMA ]${COR_RESET}"
        echo -e "${COR_AZUL}[7]${COR_RESET} Instalar Deps"
        echo -e "${COR_ROXO}[8]${COR_RESET} Configurar SMTP Gmail"
        echo -e "${COR_VERMELHO}[0]${COR_RESET} Sair"
        barra
        read -p "Opção: " op
        case $op in
            1) criar_usuario ;; 
            2) read -p "User: " u; userdel -f "$u"; grep -v "\"usuario\": \"$u\"" "$DB_PMESP" > t && mv t "$DB_PMESP" ;;
            3) atualizar_hwid ;; 
            4) recuperar_senha ;;
            5) novo_chamado ;; 
            6) gerenciar_chamados ;;
            7) install_deps ;; 
            8) configurar_smtp ;;
            0) exit 0 ;;
        esac
    done
}

menu
