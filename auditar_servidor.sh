#!/usr/bin/env bash
# =============================================================
# Auditoria C-Saude  –  OpenSCAP (CIS headless) + checks extra + Lynis
#   • Usa XML junto ao script se existir
#   • Caso contrário tenta em /usr/share/xml/scap/ssg/content/
#   • Se faltar, faz download + instala ssg-base e ssg-debderived (.deb)
#   • Gera ZIP na directoria de execução
# =============================================================

set -euo pipefail

### ------------ Funções utilitárias -------------------------
msg()  { printf '\e[1;34m%s\e[0m\n' "$*"; }
warn() { printf '\e[1;33mAVISO: %s\e[0m\n' "$*"; }
err()  { printf '\e[1;31mERRO: %s\e[0m\n'  "$*"; }

TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT INT

### ------------ Caminhos base -------------------------------
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# PROFILE="xccdf_csaude_profile_min"
TAILOR="$SELF_DIR/his-hf-tailoring.xml"         # entregue junto ao script
REPORT_DIR="$PWD"                            # ZIP sai aqui

DATE=$(date +%Y%m%dT%H%M)
HOST=$(hostname -s)

### ------------ Pacotes mínimos -----------------------------
PKGS=()
for p in libopenscap8 zip curl; do dpkg -s "$p" &>/dev/null || PKGS+=("$p"); done
if [[ ${#PKGS[@]} -gt 0 ]]; then
  msg "▶ A instalar pacotes: ${PKGS[*]}"
  sudo apt update -qq
  sudo apt install -y "${PKGS[@]}"
fi


###############################################################################
# install_latest_lynis  –  fetches Lynis 3.x from cisofy.com and installs it
###############################################################################
install_latest_lynis() {
    local VER="3.1.5"
    local URL="https://downloads.cisofy.com/lynis/lynis-${VER}.tar.gz"
    local TMP="/tmp/lynis-$RANDOM"

    msg "▶ Downloading Lynis $VER ..."
    mkdir -p "$TMP"
    curl -L --fail -o "$TMP/lynis.tar.gz" "$URL"

    msg "▶ Extracting ..."
    tar -xzf "$TMP/lynis.tar.gz" -C "$TMP"

    # the tarball expands into $TMP/lynis/
    DIR="$(find "$TMP" -maxdepth 1 -type d -name 'lynis' | head -1)"
    [[ -z "$DIR" ]] && { err "Extraction failed."; rm -rf "$TMP"; exit 1; }

    msg "▶ Installing to /usr/local/bin ..."
    sudo install -m 755 "$DIR/lynis" /usr/local/bin/lynis

    # optional: clean up
    rm -rf "$TMP"

    msg "✔ Lynis $VER installed ( $(/usr/local/bin/lynis --version) )"
}

### ------------ Função para instalar SSG (.deb) --------------
ds_download() {
  local TMP="$TMP_DIR/debs-csaude"
  mkdir -p "$TMP"
  msg "▶ A descarregar pacotes SSG (0.1.76-1)…"
  curl -L -o "$TMP/ssg-base.deb" \
    https://archive.ubuntu.com/ubuntu/pool/universe/s/scap-security-guide/ssg-base_0.1.76-1_all.deb
  curl -L -o "$TMP/ssg-debderived.deb" \
    https://archive.ubuntu.com/ubuntu/pool/universe/s/scap-security-guide/ssg-debderived_0.1.76-1_all.deb
  msg "▶ A instalar pacotes SSG…"
  sudo dpkg -i "$TMP"/*.deb || sudo apt -f install -y
  rm -rf "$TMP"/*.deb
  rmdir "$TMP"
}

### ------------ Determinar DataStream -----------------------
codename=$(grep ^VERSION_CODENAME= /etc/os-release | cut -d= -f2)
case "$codename" in
  jammy) DS_FILE="ssg-ubuntu2204-ds.xml" 
	 PROFILE="xccdf_org.ssgproject.content_profile_cis_level1_server"
	 ;;
  noble) DS_FILE="ssg-ubuntu2404-ds.xml" 
	 PROFILE="xccdf_org.ssgproject.content_profile_cis_level1_server"
	 ;;
  *) err "Ubuntu ${codename} não suportado"; exit 1 ;;
esac

path_self="$SELF_DIR/$DS_FILE"
path_system="/usr/share/xml/scap/ssg/content/$DS_FILE"

if   [[ -f "$path_self"   ]]; then CONTENT_PATH="$path_self"
elif [[ -f "$path_system" ]]; then CONTENT_PATH="$path_system"
else
  ds_download
  [[ -f "$path_system" ]] || { err "DataStream $DS_FILE não encontrado após instalação."; exit 1; }
  CONTENT_PATH="$path_system"
fi

### ------------ OpenSCAP ------------------------------------
CIS_HTML="$TMP_DIR/relatorio-cis-${HOST}-${DATE}.html"
msg "▶ A executar OpenSCAP (perfil $PROFILE)… isto pode demorar."
oscap xccdf eval \
      --profile "$PROFILE" \
      --tailoring-file "$TAILOR" \
      --report "$CIS_HTML" \
      "$CONTENT_PATH" || true     # continua mesmo com findings

### ------------ Checks personalizados (Bash) ----------------
CUSTOM_TXT="$TMP_DIR/checks-custom-${HOST}-${DATE}.txt"
msg "▶ A executar checks personalizados…"
{
  echo "=== Checks personalizados – $(date) ==="
  echo; echo "[DISCO] Partições não cifradas:"
  lsblk -pn -o NAME,FSTYPE,MOUNTPOINT | awk '$2!="crypto_LUKS" && $3!="" {print}' || echo "N/D"
  echo; echo "[ACCOUNTS] Contas genéricas activas:"
  for u in ubuntu admin admin1; do id "$u" &>/dev/null && echo "Conta $u existe"; done || true
  echo; echo "[MYSQL] require_secure_transport:"
  grep -R "require_secure_transport" /etc/mysql/mysql.conf.d 2>/dev/null || echo "Não definido"
  echo; echo "[POSTGRES] ssl=on:"
  grep -R "^[[:space:]]*ssl[[:space:]]*=" /etc/postgresql 2>/dev/null || echo "Não definido"
} > "$CUSTOM_TXT"

### ------------ Lynis ---------------------------------------
LYNIS_TXT="$TMP_DIR/lynis-${HOST}-${DATE}.txt"
install_latest_lynis
msg "▶ A executar Lynis (modo rápido)…"
sudo lynis audit system --quick --report-file "$LYNIS_TXT" --quiet
sudo /bin/cp /var/log/lynis.log "$TMP_DIR/lynis-${HOST}-${DATE}.log"
sudo /bin/cp /var/log/lynis-report.dat "$TMP_DIR/lynis-report-${HOST}-${DATE}.dat"

### ------------ ZIP + SHA-256 -------------------------------
ZIP="$REPORT_DIR/auditoria-${HOST}-${DATE}.zip"
zip -j "$ZIP" "$CIS_HTML" "$CUSTOM_TXT" "$LYNIS_TXT" "$TMP_DIR/lynis-${HOST}-${DATE}.log" "$TMP_DIR/lynis-report-${HOST}-${DATE}.dat">/dev/null
sha256sum "$ZIP" | awk '{print $1}' > "${ZIP}.sha256"
zip -j -u "$ZIP" "${ZIP}.sha256" >/dev/null
rm -f "${ZIP}.sha256"

# manter apenas três ZIPs
cd "$REPORT_DIR"
ls -1tr auditoria-*.zip | head -n -3 | xargs -r rm -f

msg "✔ ZIP criado: $ZIP"
msg "Envie este ficheiro para a equipa de segurança."

