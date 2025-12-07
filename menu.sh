#!/bin/bash
# ==================================================================
#  PMESP MANAGER ULTIMATE V8.0 - SMTP GMAIL + PROXY EDITION
#  Gestão de Usuários, Chamados, HWID, E-mail Real e Proxy.
# ==================================================================

# --- ARQUIVOS DE DADOS ---
DB_PMESP="/etc/pmesp_users.json"
DB_CHAMADOS="/etc/pmesp_tickets.json"
CONFIG_SMTP="/etc/msmtprc"
LOG_MONITOR="/var/log/pmesp_monitor.log"

# DICA:
# Para resetar manualmente o banco de usuários (CUIDADO: APAGA TUDO):
#   touch /etc/pmesp_users.json
#   chmod 666 /etc/pmesp_users.json
#   echo "" > /etc/pmesp_users.json

# Garante arquivos básicos
if [ ! -f "$DB_PMESP" ]; then
    touch "$DB_PMESP"
    chmod 666 "$DB_PMESP"
    echo "" > "$DB_PMESP"
fi

if [ ! -f "$DB_CHAMADOS" ]; then
    touch "$DB_CHAMADOS"
    chmod 666 "$DB_CHAMADOS"
fi

if [ ! -f "$LOG_MONITOR" ]; then
    touch "$LOG_MONITOR"
    chmod 644 "$LOG_MONITOR"
fi

# --- CORES ---
COR_FUNDO='\033[1;44;37m'
COR_RESET='\033[0m'
COR_VERDE='\033[1;32m'
COR_VERMELHO='\033[1;31m'
COR_AMARELO='\033[1;33m'
COR_AZUL='\033[1;34m'
COR_CIANO='\033[1;36m'
COR_ROXO='\033[1;35m'

# --- FUNÇÕES VISUAIS ---
barra() { echo -e "${COR_AZUL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COR_RESET}"; }

cabecalho() {
    clear
    echo -e "${COR_AZUL}╭━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╮${COR_RESET}"
    echo -e "${COR_AZUL}┃${COR_FUNDO}      PMESP MANAGER V8.0 - TÁTICO INTEGRADO     ${COR_RESET}${COR_AZUL}┃${COR_RESET}"
    echo -e "${COR_AZUL}╰━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╯${COR_RESET}"
}

# --- INSTALAÇÃO DE DEPENDÊNCIAS BÁSICAS ---
install_deps() {
    cabecalho
    echo -e "${COR_AMARELO}Instalando Dependências Básicas...${COR_RESET}"
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y >/dev/null 2>&1
    apt-get install -y bc screen nano net-tools lsof cron zip unzip jq msmtp msmtp-mta ca-certificates >/dev/null 2>&1

    echo -e "${COR_VERDE}Sistema Pronto! Pacotes básicos instalados.${COR_RESET}"
    sleep 2
}

# --- CONFIGURAÇÃO DO GMAIL (SMTP) ---
configurar_smtp() {
    cabecalho
    echo -e "${COR_ROXO}>>> CONFIGURAÇÃO DE SERVIDOR DE E-MAIL (GMAIL)${COR_RESET}"
    echo "Necessário ter a 'Senha de App' gerada no Google."
    echo ""

    read -p "Seu E-mail Gmail (Ex: pmesp@gmail.com): " email_adm
    read -p "Sua Senha de App (16 letras): " senha_app

    echo -e "\n${COR_AMARELO}Configurando o cliente SMTP...${COR_RESET}"

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

    chmod 600 "$CONFIG_SMTP"

    echo -e "${COR_VERDE}Configuração salva em $CONFIG_SMTP!${COR_RESET}"
    echo -e "Enviando e-mail de teste para você mesmo..."

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
        echo -e "\n${COR_VERMELHO}ERRO: Usuário já existe!${COR_RESET}"
        sleep 2
        return
    fi

    read -p "Senha Provisória: " senha
    read -p "Validade (Dias): " dias
    read -p "Limite de Telas (Sessões): " limite

    # Usuário Linux sem shell
    useradd -M -s /bin/false "$usuario"
    echo "$usuario:$senha" | chpasswd

    # Validade
    data_final=$(date -d "+$dias days" +"%Y-%m-%d")
    chage -E "$data_final" "$usuario"

    # Registra no "JSON" (1 objeto por linha)
    jq -n \
        --arg u "$usuario" \
        --arg s "$senha" \
        --arg d "$dias" \
        --arg l "$limite" \
        --arg m "$matricula" \
        --arg e "$email" \
        --arg h "PENDENTE" \
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
        echo -e "${COR_VERMELHO}Usuário não encontrado!${COR_RESET}"
        sleep 2
        return
    fi

    linha=$(grep "\"usuario\": \"$user_alvo\"" "$DB_PMESP")
    s=$(echo "$linha" | jq -r .senha)
    d=$(echo "$linha" | jq -r .dias)
    l=$(echo "$linha" | jq -r .limite)
    m=$(echo "$linha" | jq -r .matricula)
    e=$(echo "$linha" | jq -r .email)

    grep -v "\"usuario\": \"$user_alvo\"" "$DB_PMESP" > "${DB_PMESP}.tmp" && mv "${DB_PMESP}.tmp" "$DB_PMESP"

    jq -n \
        --arg u "$user_alvo" \
        --arg s "$s" \
        --arg d "$d" \
        --arg l "$l" \
        --arg m "$m" \
        --arg e "$e" \
        --arg h "$novo_hwid" \
        '{usuario: $u, senha: $s, dias: $d, limite: $l, matricula: $m, email: $e, hwid: $h}' \
        >> "$DB_PMESP"

    echo -e "${COR_VERDE}HWID Atualizado.${COR_RESET}"
    sleep 2
}

# --- GERENCIAR USUÁRIOS (LISTAR / REMOVER / ALTERAR DATA / VER ONLINE) ---
gerenciar_usuarios() {
    while true; do
        cabecalho
        echo -e "${COR_VERDE}>>> GERENCIAR USUÁRIOS${COR_RESET}"
        barra

        idx=1
        unset usuarios
        declare -a usuarios

        # Só tenta ler se o arquivo não estiver vazio
        if [ -s "$DB_PMESP" ]; then
            # Lê cada usuário como um JSON completo (mesmo que esteja em várias linhas no arquivo)
            while IFS= read -r line; do
                [ -z "$line" ] && continue

                usuario=$(echo "$line" | jq -r '.usuario // empty' 2>/dev/null)
                [ -z "$usuario" ] && continue
                [ "$usuario" = "null" ] && continue

                matricula=$(echo "$line" | jq -r '.matricula // "-"')
                email=$(echo "$line" | jq -r '.email // "-"')
                dias=$(echo "$line" | jq -r '.dias // "-"')
                limite=$(echo "$line" | jq -r '.limite // "-"')
                hwid=$(echo "$line" | jq -r '.hwid // "-"')

                printf "%3s) %-15s | MAT: %-10s | DIAS: %-5s | LIM: %-3s | EMAIL: %-20s | HWID: %s\n" \
                    "$idx" "$usuario" "$matricula" "$dias" "$limite" "$email" "$hwid"

                usuarios[$idx]="$usuario"
                idx=$((idx + 1))
            done < <(jq -c '.' "$DB_PMESP" 2>/dev/null)
        fi

        if [ "$idx" -eq 1 ]; then
            echo "Nenhum usuário cadastrado."
        fi

        echo ""
        echo "[0] Voltar"
        read -p "Selecione o número do usuário para gerenciar: " escolha

        if [ "$escolha" = "0" ] || [ -z "$escolha" ]; then
            return
        fi

        user_sel="${usuarios[$escolha]}"
        if [ -z "$user_sel" ]; then
            echo -e "${COR_VERMELHO}Opção inválida.${COR_RESET}"
            sleep 1.5
            continue
        fi

        echo ""
        echo -e "Selecionado: ${COR_AMARELO}$user_sel${COR_RESET}"
        echo "[1] Remover usuário"
        echo "[2] Alterar validade (dias)"
        echo "[3] Verificar se está online agora"
        echo "[0] Voltar"
        read -p "Opção: " acao

        case "$acao" in
            1)
                userdel -f "$user_sel" >/dev/null 2>&1
                tmp=$(mktemp)
                jq -c --arg u "$user_sel" 'select(.usuario != $u)' "$DB_PMESP" > "$tmp" && mv "$tmp" "$DB_PMESP"
                chmod 666 "$DB_PMESP"
                echo -e "${COR_VERDE}Usuário $user_sel removido.${COR_RESET}"
                sleep 1.5
                ;;
            2)
                read -p "Nova validade em dias a partir de hoje: " novos_dias
                if ! [[ "$novos_dias" =~ ^[0-9]+$ ]]; then
                    echo -e "${COR_VERMELHO}Valor inválido.${COR_RESET}"
                    sleep 1.5
                else
                    nova_data=$(date -d "+$novos_dias days" +"%Y-%m-%d")
                    chage -E "$nova_data" "$user_sel"

                    tmp=$(mktemp)
                    jq -c --arg u "$user_sel" --arg d "$novos_dias" \
                       'if .usuario == $u then .dias = $d else . end' \
                       "$DB_PMESP" > "$tmp" && mv "$tmp" "$DB_PMESP"
                    chmod 666 "$DB_PMESP"

                    echo -e "${COR_VERDE}Validade atualizada para $novos_dias dias (até $nova_data).${COR_RESET}"
                    sleep 1.5
                fi
                ;;
            3)
                sessoes=$(who | awk -v user="$user_sel" '$1==user {c++} END {print c+0}')
                linha=$(jq -c --arg u "$user_sel" 'select(.usuario == $u)' "$DB_PMESP" | head -n1)
                limite=$(echo "$linha" | jq -r '.limite // "0"')
                echo -e "Sessões ativas: ${COR_AMARELO}$sessoes${COR_RESET} / Limite configurado: ${COR_AMARELO}$limite${COR_RESET}"
                read -p "Enter para continuar..." _
                ;;
            *)
                ;;
        esac
    done
}


# --- SISTEMA DE CHAMADOS ---
novo_chamado() {
    cabecalho
    echo -e "${COR_CIANO}>>> NOVO CHAMADO${COR_RESET}"
    ID=$((1000 + RANDOM % 8999))
    DATA=$(date "+%d/%m/%Y %H:%M")
    read -p "Usuário: " user
    read -p "Problema: " prob

    jq -n \
        --arg i "$ID" \
        --arg u "$user" \
        --arg p "$prob" \
        --arg s "ABERTO" \
        --arg d "$DATA" \
        '{id: $i, usuario: $u, problema: $p, status: $s, data: $d}' \
        >> "$DB_CHAMADOS"

    echo -e "${COR_VERDE}Chamado #$ID criado.${COR_RESET}"
    sleep 2
}

gerenciar_chamados() {
    while true; do
        cabecalho
        echo -e "${COR_CIANO}>>> GERENCIAR CHAMADOS${COR_RESET}"
        printf "${COR_AZUL}%-6s | %-12s | %-10s | %-20s${COR_RESET}\n" "ID" "USER" "STATUS" "DESC"
        barra

        while read -r line; do
            [ -z "$line" ] && continue
            i=$(echo "$line" | jq -r .id)
            u=$(echo "$line" | jq -r .usuario)
            p=$(echo "$line" | jq -r .problema)
            s=$(echo "$line" | jq -r .status)

            if [ "$s" == "ABERTO" ]; then
                C=$COR_VERMELHO
            else
                C=$COR_VERDE
            fi

            printf "%-6s | %-12s | ${C}%-10s${COR_RESET} | %-20s\n" "$i" "$u" "$s" "${p:0:20}..."
        done < "$DB_CHAMADOS"

        echo ""
        echo "[1] Fechar Chamado | [2] Deletar Chamado | [0] Voltar"
        read -p "Op: " opc

        case $opc in
            1)
                read -p "ID: " id
                tmp=$(mktemp)
                while read -r l; do
                    [ -z "$l" ] && continue
                    cid=$(echo "$l" | jq -r .id)
                    if [ "$cid" == "$id" ]; then
                        echo "$l" | jq '.status="ENCERRADO"' >> "$tmp"
                    else
                        echo "$l" >> "$tmp"
                    fi
                done < "$DB_CHAMADOS"
                mv "$tmp" "$DB_CHAMADOS"
                ;;
            2)
                read -p "ID: " id
                grep -v "\"id\": \"$id\"" "$DB_CHAMADOS" > t.json && mv t.json "$DB_CHAMADOS"
                ;;
            0)
                return
                ;;
        esac
    done
}

# --- RECUPERAÇÃO DE SENHA (COM SMTP REAL) ---
recuperar_senha() {
    cabecalho
    echo -e "${COR_ROXO}>>> RESETAR SENHA E ENVIAR EMAIL${COR_RESET}"

    if [ ! -f "$CONFIG_SMTP" ]; then
        echo -e "${COR_VERMELHO}ERRO: Configure o SMTP (Opção 8) primeiro!${COR_RESET}"
        sleep 3
        return
    fi

    read -p "Usuário para reset: " user_alvo

    if ! grep -q "\"usuario\": \"$user_alvo\"" "$DB_PMESP"; then
        echo -e "${COR_VERMELHO}Usuário não existe.${COR_RESET}"
        sleep 2
        return
    fi

    linha=$(grep "\"usuario\": \"$user_alvo\"" "$DB_PMESP")
    email_dest=$(echo "$linha" | jq -r .email)

    if [ -z "$email_dest" ] || [ "$email_dest" == "null" ]; then
        echo -e "${COR_VERMELHO}Usuário sem e-mail cadastrado.${COR_RESET}"
        sleep 2
        return
    fi

    nova_senha=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
    echo "$user_alvo:$nova_senha" | chpasswd

    grep -v "\"usuario\": \"$user_alvo\"" "$DB_PMESP" > "${DB_PMESP}.tmp" && mv "${DB_PMESP}.tmp" "$DB_PMESP"

    jq -n \
        --arg u "$user_alvo" \
        --arg s "$nova_senha" \
        --arg d "$(echo "$linha" | jq -r .dias)" \
        --arg l "$(echo "$linha" | jq -r .limite)" \
        --arg m "$(echo "$linha" | jq -r .matricula)" \
        --arg e "$email_dest" \
        --arg h "$(echo "$linha" | jq -r .hwid)" \
        '{usuario: $u, senha: $s, dias: $d, limite: $l, matricula: $m, email: $e, hwid: $h}' \
        >> "$DB_PMESP"

    echo -e "Enviando e-mail para ${COR_AMARELO}$email_dest${COR_RESET}..."

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

# --- MOSTRAR USUÁRIOS ONLINE (INTERATIVO) ---
mostrar_usuarios_online() {
    cabecalho
    echo -e "${COR_CIANO}>>> USUÁRIOS ONLINE AGORA${COR_RESET}"
    barra
    printf "%-15s | %-8s | %-6s\n" "Usuário" "Sessões" "Limite"
    barra

    while read -r line; do
        [ -z "$line" ] && continue
        user=$(echo "$line" | jq -r '.usuario' 2>/dev/null)
        [ -z "$user" ] && continue
        [ "$user" = "null" ] && continue

        limite=$(echo "$line" | jq -r '.limite')
        [ -z "$limite" ] && limite=0

        sessoes=$(who | awk -v user="$user" '$1==user {c++} END {print c+0}')

        if [ "$sessoes" -gt 0 ]; then
            printf "%-15s | %-8s | %-6s\n" "$user" "$sessoes" "$limite"
        fi
    done < "$DB_PMESP"

    echo ""
    read -p "Enter para voltar..." _
}

# --- MONITORAR ACESSOS (PARA CRON) ---
monitorar_acessos() {
    while read -r line; do
        [ -z "$line" ] && continue
        user=$(echo "$line" | jq -r '.usuario' 2>/dev/null)
        [ -z "$user" ] && continue
        [ "$user" = "null" ] && continue

        limite=$(echo "$line" | jq -r '.limite')
        [ -z "$limite" ] && limite=0

        sessoes=$(who | awk -v user="$user" '$1==user {c++} END {print c+0}')

        if [ "$sessoes" -gt 0 ]; then
            echo "$(date '+%F %T') | user=$user | sessoes=$sessoes | limite=$limite" >> "$LOG_MONITOR"

            if [ "$limite" -gt 0 ] && [ "$sessoes" -gt "$limite" ]; then
                echo "$(date '+%F %T') | LIMITE EXCEDIDO: $user (sessoes=$sessoes, limite=$limite)" >> "$LOG_MONITOR"
                # Se quiser derrubar sessões excedentes, descomente a linha abaixo:
                # pkill -KILL -u "$user"
            fi
        fi
    done < "$DB_PMESP"
}

# --- CONFIGURAR CRON PARA MONITORAR ACESSOS ---
configurar_cron_monitor() {
    cabecalho
    echo -e "${COR_CIANO}>>> CONFIGURAR CRON PARA MONITORAR ACESSOS${COR_RESET}"
    script_path=$(readlink -f "$0")
    echo "Script atual: $script_path"
    echo ""
    echo "Será criado/atualizado um cron a cada 1 minuto:"
    echo "  */1 * * * * /bin/bash $script_path --cron-monitor"
    echo ""
    read -p "Confirmar? (s/N): " resp
    case "$resp" in
        s|S|y|Y)
            (
                crontab -l 2>/dev/null | grep -v -- "--cron-monitor"
                echo "*/1 * * * * /bin/bash $script_path --cron-monitor >/dev/null 2>&1"
            ) | crontab -
            echo -e "${COR_VERDE}Cron configurado com sucesso.${COR_RESET}"
            ;;
        *)
            echo "Cancelado."
            ;;
    esac
    sleep 2
}

# --- INSTALAR SQUID (PROXY HTTP LIBERADO) ---
install_squid() {
    cabecalho
    echo -e "${COR_CIANO}>>> INSTALAÇÃO DO SQUID (PROXY HTTP)${COR_RESET}"
    echo "Instalando pacote squid..."
    apt-get update -y >/dev/null 2>&1
    apt-get install -y squid >/dev/null 2>&1

    if [ -f /etc/squid/squid.conf ]; then
        cp /etc/squid/squid.conf "/etc/squid/squid.conf.bak_$(date +%F_%H%M%S)"
    fi

    cat <<EOF >/etc/squid/squid.conf
# ============================================
#  SQUID - CONFIG BÁSICA PMESP MANAGER
#  Proxy liberado (ajuste ACL depois se quiser)
# ============================================
http_port 3128

acl all src 0.0.0.0/0
http_access allow all

cache_mem 64 MB
maximum_object_size_in_memory 512 KB
cache_dir ufs /var/spool/squid 100 16 256

access_log daemon:/var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
EOF

    systemctl enable squid >/dev/null 2>&1
    systemctl restart squid

    echo ""
    echo -e "${COR_VERDE}SQUID instalado e rodando na porta 3128.${COR_RESET}"
    echo "No Windows, configure o navegador para usar o PROXY HTTP:"
    echo "  IP da VPS  : porta 3128"
    echo ""
    echo -e "${COR_AMARELO}ATENÇÃO:${COR_RESET} esta configuração libera acesso geral."
    echo "Edite /etc/squid/squid.conf depois para restringir por IP, se quiser."
    read -p "Enter para voltar..." _
}

# --- INSTALAR SSLH NA PORTA 443 ---
install_sslh() {
    cabecalho
    echo -e "${COR_ROXO}>>> INSTALAÇÃO DO SSLH NA PORTA 443${COR_RESET}"
    echo "Isso permite usar SSH na porta 443, por exemplo:"
    echo "  ssh -D 1080 -p 443 user@IP_DA_VPS"
    echo "E depois no Firefox usar SOCKS 127.0.0.1:1080 (como você fazia na PM)."
    echo ""

    apt-get update -y >/dev/null 2>&1
    apt-get install -y sslh >/dev/null 2>&1

    if [ -f /etc/default/sslh ]; then
        cp /etc/default/sslh "/etc/default/sslh.bak_$(date +%F_%H%M%S)"
    fi

    cat <<'EOF' >/etc/default/sslh
# PMESP MANAGER - CONFIG SSLH
RUN=yes

DAEMON_OPTS="--user sslh --listen 0.0.0.0:443 \
--ssh 127.0.0.1:22 \
--pidfile /run/sslh/sslh.pid"
EOF

    systemctl enable sslh >/dev/null 2>&1
    systemctl restart sslh

    echo -e "${COR_VERDE}SSLH configurado na porta 443 redirecionando para SSH (22).${COR_RESET}"
    echo ""
    echo "Lembre-se de liberar a porta 443 no firewall da VPS (iptables/ufw)."
    read -p "Enter para voltar..." _
}

# --- MENU PRINCIPAL ---
menu() {
    while true; do
        cabecalho
        echo -e "   ${COR_VERDE}[ GESTÃO ]${COR_RESET}"
        echo -e "${COR_AMARELO}[1]${COR_RESET} Criar Usuário"
        echo -e "${COR_AMARELO}[2]${COR_RESET} Gerenciar Usuários (listar/remover/validade/online)"
        echo -e "${COR_AMARELO}[3]${COR_RESET} Vincular HWID"
        echo -e "${COR_AMARELO}[4]${COR_RESET} Resetar Senha (Email)"
        echo ""
        echo -e "   ${COR_VERDE}[ SUPORTE ]${COR_RESET}"
        echo -e "${COR_CIANO}[5]${COR_RESET} Abrir Chamado"
        echo -e "${COR_CIANO}[6]${COR_RESET} Gerenciar Chamados"
        echo ""
        echo -e "   ${COR_VERDE}[ SISTEMA ]${COR_RESET}"
        echo -e "${COR_AZUL}[7]${COR_RESET} Instalar Dependências Básicas"
        echo -e "${COR_ROXO}[8]${COR_RESET} Configurar SMTP Gmail"
        echo -e "${COR_CIANO}[9]${COR_RESET} Instalar Squid Proxy"
        echo -e "${COR_CIANO}[10]${COR_RESET} Instalar SSLH na porta 443"
        echo -e "${COR_CIANO}[11]${COR_RESET} Ver Usuários Online"
        echo -e "${COR_CIANO}[12]${COR_RESET} Configurar Cron Monitor Acessos"
        echo -e "${COR_VERMELHO}[0]${COR_RESET} Sair"
        barra
        read -p "Opção: " op
        case $op in
            1) criar_usuario ;;
            2) gerenciar_usuarios ;;
            3) atualizar_hwid ;;
            4) recuperar_senha ;;
            5) novo_chamado ;;
            6) gerenciar_chamados ;;
            7) install_deps ;;
            8) configurar_smtp ;;
            9) install_squid ;;
            10) install_sslh ;;
            11) mostrar_usuarios_online ;;
            12) configurar_cron_monitor ;;
            0) exit 0 ;;
        esac
    done
}

# --- MODO CRON (APENAS MONITORAR) ---
if [ "$1" == "--cron-monitor" ]; then
    monitorar_acessos
    exit 0
fi

# --- INÍCIO ---
menu
