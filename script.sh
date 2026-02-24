#!/bin/bash

# Variabel Warna
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color / Reset

# Fungsi untuk menampilkan pesan
success() {
    echo -e " ${GREEN}[ - SUCCESS - ]${NC} $1"
}

error() {
    echo -e " ${RED}[ - ERROR - ]${NC} $1"
}

warning() {
    echo -e " ${YELLOW}[ - WARNING - ]${NC} $1"
}

info() {
    echo -e " ${BLUE}[ - INFO - ]${NC} $1"
}

setup() {
    # Update & Upgrade
    info "Updating.."
    sudo apt update -y
    success "Success updating"
        
    info "Upgrading.."
    sudo apt upgrade -y
    success "Success upgrading"
        
    # Install semua paket (Perbaikan: 'Info' jadi 'info')
    info "Installing all required package.."
    sudo apt install -y bc bison build-essential curl flex g++-multilib gcc-multilib git gnupg gperf libxml2 lib32z1-dev liblz4-tool libncurses5-dev libsdl1.2-dev libwxgtk3.2-dev imagemagick ccache lunzip lzop array-info schedtool squashfs-tools xsltproc zip zlib1g-dev openjdk-11-jdk-headless python3 python-is-python3 python3-venv perl xmlstarlet virtualenv xz-utils rr jq libncurses5 pngcrush lib32ncurses5-dev git-lfs

    # Download & setup platform-tools
    cd ~
    info "Downloading platform-tools.."
    wget -q --show-progress -O platform-tools.zip https://dl.google.com/android/repository/platform-tools-latest-linux.zip
    unzip -q platform-tools.zip 
        
    if ! grep -q "platform-tools" ~/.profile; then
        cat << 'EOF' >> ~/.profile

if [ -d "$HOME/platform-tools" ] ; then
    PATH="$HOME/platform-tools:$PATH"
fi
EOF
    fi

    # Install command repo
    mkdir -p ~/bin
    curl -s https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
    chmod a+x ~/bin/repo
        
    # Tambahkan ~/bin ke PATH jika belum ada
    if ! grep -q "$HOME/bin" ~/.profile; then
        info "Adding path $HOME/bin to ~/.profile..."
        cat << 'EOF' >> ~/.profile

if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi
EOF
    else
        info "$HOME/bin already exist, skipping."
    fi
    
    source ~/.profile

    # Konfigurasi git
    git config --global user.name "Han"
    git config --global user.email han@mail.com
        
    # Menggunakan ccache
    export USE_CCACHE=1
    export CCACHE_COMPRESS=1
    export CCACHE_MAXSIZE=50G
        
    success "Success setup! Script will continue to building"
}

build() {
    # Buat direktori
    mkdir -p infinity
    cd infinity || exit
        
    # Inisialisasi local repo
    info "Initializing Repo.."
    repo init --depth=1 --no-repo-verify --git-lfs -u https://github.com/ProjectInfinity-X/manifest -b 15 -g default,-mips,-darwin,-notdefault
        
    # Sync
    info "Sync-ing (This may take a long time).."
    repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j$(nproc --all)
        
    # Clone semua repo yang dibutuhkan
    info "Cloning dependencies.."
    git clone https://github.com/TrebleDroid/vendor_interfaces -b android-15.0 vendor/interfaces
    git clone https://github.com/TrebleDroid/device_phh_treble -b android-15.0 device/phh/treble
    git clone https://github.com/TrebleDroid/treble_app -b master treble_app
    git clone https://github.com/AndyCGYan/android_packages_apps_QcRilAm -b master packages/apps/QcRilAm
    git clone https://github.com/TrebleDroid/vendor_hardware_overlay -b pie vendor/hardware_overlay
    git clone https://android.googlesource.com/platform/prebuilts/vndk/v28 prebuilts/vndk/v28
    git clone https://android.googlesource.com/platform/prebuilts/vndk/v29 prebuilts/vndk/v29
    git clone https://github.com/ponces/treble_adapter -b master treble_adapter
    git clone https://github.com/Doze-off/patches.git -b patches-15 patches
        
    # Pindah file apply-patches.sh ke direktori utama
    if [ -f "patches/apply-patches.sh" ]; then
        mv patches/apply-patches.sh .
        success "Moved apply-patches.sh to root"
    fi

    # 2. PINDAHKAN FILE MK KE device/phh/treble
    info "Moving Infinity Treble configurations..."
    
    FILES_TO_MOVE=("AndroidProducts.mk" "infinity.mk" "infinity_gsi.mk")
    DEST="device/phh/treble"

    for file in "${FILES_TO_MOVE[@]}"; do
        # Cek apakah file ada di root atau di dalam folder patches
        if [ -f "$file" ]; then
            mv "$file" "$DEST/"
            success "Moved $file to $DEST"
        elif [ -f "patches/$file" ]; then
            mv "patches/$file" "$DEST/"
            success "Moved $file (from patches) to $DEST"
        else
            warning "File $file not found, make sure it exists!"
        fi
    done

    # Apply patches-nya
        bash apply-patches.sh ~/infinity
        
    # Build
        source build/envsetup.sh
        lunch infinity_gsi-userdebug
        m systemimage -j$(nproc --all)
        
    # Kompress hasilnya
        xz -9 -T0 -v -z out/target/product/tdgsi_arm64_ab/system.img
}

upload_gofile() {
    local FILE_PATH=$1
    if [ ! -f "$FILE_PATH" ]; then
        error "File $FILE_PATH not dound!"
        return 1
    fi

    info "Finding the best server..."
    # Ambil server terbaik dari API GoFile
    SERVER=$(curl -s https://api.gofile.io/servers | jq -r '.data.servers[0].name')

    info "Uploading $FILE_PATH to $SERVER..."
    # Proses Upload
    RESPONSE=$(curl -F "file=@$FILE_PATH" "https://${SERVER}.gofile.io/contents/uploadfile")
    
    # Cek apakah berhasil dan ambil link-nya
    STATUS=$(echo $RESPONSE | jq -r '.status')
    if [ "$STATUS" == "ok" ]; then
        DOWNLOAD_LINK=$(echo $RESPONSE | jq -r '.data.downloadPage')
        success "Done uploading, link : $DOWNLOAD_LINK"
        echo "gofile_url=$DOWNLOAD_LINK" >> $GITHUB_OUTPUT
    # Simpan link ke file agar bisa dibaca oleh step GitHub Action berikutnya
        echo "$DOWNLOAD_LINK" > gofile_link.txt
    else
        error "Failed to upload result"
        echo $RESPONSE
    fi
}

# Menjalankan fungsi
setup
build
