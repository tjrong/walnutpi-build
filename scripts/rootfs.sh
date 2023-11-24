#!/bin/bash

OPT_OS_VER=""
OPT_ROOTFS_TYPE=""
PATH_ROOTFS=""
FILE_ROOTFS_TAR=""



choose_rootfs() {
    # 只测试了bookworm的软件兼容性问题，有些库不确定能不能在旧版debian上运行
    # titlestr="Choose an version"
    # options+=("bookworm"    "debian 12(bookworm)")
    # options+=("bullseye"    "debian 11(bullseye)")
    # options+=("buster"  "debian 10(buster)")
    # OPT_OS_VER=$(whiptail --title "${titlestr}" --backtitle "${backtitle}" --notags \
    #             --menu "${menustr}" "${TTY_Y}" "${TTY_X}" $((TTY_Y - 8))  \
    #             --cancel-button Exit --ok-button Select "${options[@]}" \
    #             3>&1 1>&2 2>&3)
    # unset options
    # echo ${OPT_OS_VER}
    # [[ -z ${OPT_OS_VER} ]] && exit
    
    
    OPT_OS_VER="bookworm"
    
    titlestr="Server or Graphics"
    options+=("server"    "server")
    options+=("desktop"    "desktop")
    OPT_ROOTFS_TYPE=$(whiptail --title "${titlestr}" --backtitle "${backtitle}" --notags \
        --menu "${menustr}" "${TTY_Y}" "${TTY_X}" $((TTY_Y - 8))  \
        --cancel-button Exit --ok-button Select "${options[@]}" \
    3>&1 1>&2 2>&3)
    unset options
    echo $OPT_ROOTFS_TYPE
    [[ -z $OPT_ROOTFS_TYPE ]] && exit
    
    FILE_ROOTFS_TAR="${PATH_OUTPUT}/rootfs_${OPT_OS_VER}_${OPT_ROOTFS_TYPE}.tar.gz"
    PATH_ROOTFS=${PATH_TMP}/${OPT_OS_VER}_${OPT_ROOTFS_TYPE}
    
    # titlestr="Choose  Language"
    # options+=("cn"    "Chinese")
    # options+=("en"    "English")
    # OPT_LANGUAGE=$(whiptail --title "${titlestr}" --backtitle "${backtitle}" --notags \
    #             --menu "${menustr}" "${TTY_Y}" "${TTY_X}" $((TTY_Y - 8))  \
    #             --cancel-button Exit --ok-button Select "${options[@]}" \
    #             3>&1 1>&2 2>&3)
    # unset options
    # echo $OPT_LANGUAGE
    # [[ -z $OPT_LANGUAGE ]] && exit
    
}

create_rootfs() {
    set -e
    run_as_client umount_chroot $PATH_ROOTFS
    rm -r ${PATH_ROOTFS}
    
    echo -e "\n\n------\t build rootfs \t------"
    
    PATH_SAVE_ROOTFS=${PATH_SOURCE}/${OPT_OS_VER}_${CHIP_ARCH}
    if [[ -d $PATH_SAVE_ROOTFS ]]; then
        cp -r $PATH_SAVE_ROOTFS $PATH_ROOTFS
    else
        run_as_client mkdir ${PATH_ROOTFS} -p
        if [[ $(curl -s ipinfo.io/country) =~ ^(CN|HK)$ ]]; then
            debootstrap --foreign --verbose  --arch=${CHIP_ARCH} ${OPT_OS_VER} ${PATH_ROOTFS}  http://mirrors.tuna.tsinghua.edu.cn/debian/
        else
            debootstrap --foreign --verbose  --arch=${CHIP_ARCH} ${OPT_OS_VER} ${PATH_ROOTFS}  http://ftp.cn.debian.org/debian/
            
        fi
        
        exit_if_last_error
        
        qemu_arch=""
        case "${CHIP_ARCH}" in
            "arm64")
                qemu_arch="aarch64"
            ;;
            "arm")
                qemu_arch="arm"
            ;;
        esac
        cp /usr/bin/qemu-${qemu_arch}-static ${PATH_ROOTFS}/usr/bin/
        chmod +x ${PATH_ROOTFS}/usr/bin/qemu-${qemu_arch}-static
        
        # 完成rootfs的初始化
        cd ${PATH_ROOTFS}
        mount_chroot $PATH_ROOTFS
        LC_ALL=C LANGUAGE=C LANG=C chroot ${PATH_ROOTFS} /debootstrap/debootstrap --second-stage –verbose
        exit_if_last_error
        
        # cd ${PATH_ROOTFS}
        umount_chroot $PATH_ROOTFS
        cp -r $PATH_ROOTFS $PATH_SAVE_ROOTFS
    fi
    
    # 创建release文件
    relseas_file="${PATH_ROOTFS}/etc/WalnutPi-release"
    touch $relseas_file
    echo "version=$(cat $PATH_PWD/VERSION)" >> $relseas_file
    echo "date=$(date "+%Y-%m-%d %H:%M")" >> $relseas_file
    echo "os_type=${OPT_ROOTFS_TYPE}"  >> $relseas_file
    echo ""   >> $relseas_file
    echo "kernel_git=$LINUX_GIT"  >> $relseas_file
    echo "kernel_version=$LINUX_BRANCH"  >> $relseas_file
    echo "kernel_config=$LINUX_CONFIG"  >> $relseas_file
    echo "toolchain=$TOOLCHAIN_FILE_NAME"  >> $relseas_file
    # echo -e "\n\n[update-info]"   >> $relseas_file
    # echo "$(cat $PATH_PWD/update-info)" >> $relseas_file
    
    cat $relseas_file
    
    cd $PATH_ROOTFS
    mount_chroot $PATH_ROOTFS
    
    # # clone 相关项目
    # mapfile -t git_links < <(grep -vE '^#|^$' "$FILE_GIT_LIST")
    # total=${#git_links[@]}
    # for i in "${!git_links[@]}"; do
    #     link="${git_links[$i]}"
    #     project_name=$(basename "$link" .git)
    #     run_status "clone/pull [$((i+1))/${total}] : $project_name "  clone_url $PATH_SOURCE $link
    #     cp -r ${PATH_SOURCE}/${project_name} ${PATH_ROOTFS}/opt
    # done
    
    # 插入walnutpi的apt源
    echo $APT_SOURCES_WALNUT >> ${PATH_ROOTFS}/etc/apt/sources.list
    
    # apt安装通用软件
    PATH_APT_CACHE="${PATH_TMP}/apt_cache_${OPT_OS_VER}_${CHIP_ARCH}"
    if [ ! -d $PATH_APT_CACHE ]; then
        mkdir $PATH_APT_CACHE
    fi
    run_as_client cp -r ${PATH_APT_CACHE}/* ${PATH_ROOTFS}/var/cache/apt/archives/
    run_status "apt update" chroot ${PATH_ROOTFS} /bin/bash -c "apt-get update"
    
    mapfile -t packages < <(grep -vE '^#|^$' ${FILE_APT_BASE})
    if [[ ${OPT_ROOTFS_TYPE} == "desktop" ]]; then
        mapfile -t desktop_packages  < <(grep -vE '^#|^$' ${FILE_APT_DESKTOP})
        packages=("${packages[@]}" "${desktop_packages[@]}")
    fi
    total=${#packages[@]}
    for (( i=0; i<${total}; i++ )); do
        package=${packages[$i]}
        run_status "apt [$((i+1))/${total}] : $package " chroot $PATH_ROOTFS /bin/bash -c "DEBIAN_FRONTEND=noninteractive  apt-get install -y  ${package}"
    done
    # run_status "apt  ${packages[*]} " chroot $PATH_ROOTFS /bin/bash -c "DEBIAN_FRONTEND=noninteractive  apt-get install -y  ${packages[*]}"
    
    run_as_client cp -r  ${PATH_ROOTFS}/var/cache/apt/archives/* ${PATH_APT_CACHE}/
    run_client_when_successfuly chroot $PATH_ROOTFS /bin/bash -c "DEBIAN_FRONTEND=noninteractive  apt-get clean"
    
    
    # # 安装本项目保存的deb包
    # find $PATH_FS_DEB_BASE -type f -name "*.deb" -exec cp {} ${PATH_ROOTFS}/opt/ \;
    # if [ "$OPT_ROOTFS_TYPE" = "desktop" ]; then
    #     find $PATH_FS_DEB_DESK -type f -name "*.deb" -exec cp {} ${PATH_ROOTFS}/opt/ \;
    # fi
    
    # declare -a debs_array
    # for file in ${PATH_ROOTFS}/opt/*.deb; do
    #     debs_array+=("${file}")
    # done
    # for (( i=0; i<${#debs_array[@]}; i++ )); do
    #     file=${debs_array[$i]}
    #     chmod +x $file
    #     file_name=$(basename -- "${file}")
    #     # echo "running script [$((i+1))/${#debs_array[@]}] $file_name"
    #     run_status "debs [$((i+1))/${#debs_array[@]}] $file_name" chroot  $PATH_ROOTFS /bin/bash -c "export HOME=/root; cd /opt/ &&  dpkg -i ${file_name}"
    #     _try_command rm $file
    # done
    
    # pip 安装指定软件
    # 删除一个用于禁止pip安装的文件 如在debian12中是/usr/lib/python3.11/EXTERNALLY-MANAGED
    LIB_DIR="${PATH_ROOTFS}/usr/lib"
    FILE_NAME="EXTERNALLY-MANAGED"
    find $LIB_DIR -type f -name "$FILE_NAME"  -delete
    mapfile -t packages < <(grep -vE '^#|^$' ${FILE_PIP_LIST})
    total=${#packages[@]}
    for (( i=0; i<${total}; i++ )); do
        package=${packages[$i]}
        # echo "pip3 [$((i+1))/${total}] : $package"
        run_status "pip3 [$((i+1))/${total}] : $package" chroot $PATH_ROOTFS /bin/bash -c "DEBIAN_FRONTEND=noninteractive  pip3 --no-cache-dir install   ${package}"
    done
    
    # umount_chroot $PATH_ROOTFS
    # exit -1
    
    # firmware
    cd ${PATH_SOURCE}
    firm_dir=$(basename "${FIRMWARE_GIT}" .git)
    if [ -n "${FIRMWARE_GIT}" ]; then
        if [[ ! -d "firmware" ]]; then
            run_status "download firmware" git clone "${FIRMWARE_GIT}"
        fi
        cp -r ${firm_dir}/* ${PATH_ROOTFS}/lib/firmware
    fi
    
    
    # 驱动
    if [ -d "${PATH_OUTPUT}" ]; then
        cp -r ${PATH_OUTPUT}/lib/* ${PATH_ROOTFS}/lib/
    fi
    MODULES_LIST=$(echo ${MODULES_ENABLE} | tr ' ' '\n')
    echo "$MODULES_LIST" > ${PATH_ROOTFS}/etc/modules
    
    
    # # 启用通用service
    SYSTEMD_DIR="${PATH_ROOTFS}/lib/systemd/system/"
    WALNUTPI_DIR="${PATH_ROOTFS}/usr/lib/walnutpi/"
    # mkdir -p "$WALNUTPI_DIR"
    # for file in "$PATH_SERVICE"/*; do
    #     # echo $file
    #     if [[ $file == *.service ]]; then
    #         cp $file $SYSTEMD_DIR
    #         run_status "enable service\t${file}" chroot ${PATH_ROOTFS} /bin/bash -c "systemctl enable  $(basename "$file" .service)"
    #     else
    #         cp "$file" "$WALNUTPI_DIR"
    #         chmod +x "${WALNUTPI_DIR}/$(basename $file)"
    #     fi
    # done
    
    
    # # 启用board自带service
    # for file in ${CONF_DIR}/service/*.service; do
    #     echo $file
    #     cp $file $SYSTEMD_DIR
    #     run_status "enable service\t${file}" chroot ${PATH_ROOTFS} /bin/bash -c "systemctl enable  $(basename "$file" .service)"
    
    # done
    
    
    
    # # 复制脚本进rootfs内执行
    # shopt -s dotglob
    # find $PATH_S_FS_BASE -type f -name "*.sh" -exec cp {} ${PATH_ROOTFS}/opt/ \;
    # cp -r ${PATH_S_FS_BASE_RESOURCE}/. ${PATH_ROOTFS}/opt/
    
    # find ${PATH_S_FS_USER}/ -type f -name "*.sh" -exec cp {} ${PATH_ROOTFS}/opt/ \;
    # cp -r ${PATH_S_FS_USER_RESOURCE}/. ${PATH_ROOTFS}/opt/
    
    # if [ "$OPT_ROOTFS_TYPE" = "desktop" ]; then
    #     find $PATH_S_FS_DESK -type f -name "*.sh" -exec cp {} ${PATH_ROOTFS}/opt/ \;
    #     cp -r ${PATH_S_FS_DESK_RESOURCE}/. ${PATH_ROOTFS}/opt/
    # fi
    
    # declare -a files_array
    # for file in ${PATH_ROOTFS}/opt/*.sh; do
    #     files_array+=("${file}")
    # done
    # for (( i=0; i<${#files_array[@]}; i++ )); do
    #     file=${files_array[$i]}
    #     chmod +x $file
    #     file_name=$(basename -- "${file}")
    #     # echo "running script [$((i+1))/${#files_array[@]}] $file_name"
    #     run_status "running script [$((i+1))/${#files_array[@]}] $file_name" chroot  $PATH_ROOTFS /bin/bash -c "export HOME=/root; cd /opt/ && ./${file_name}"
    #     _try_command rm $file
    # done
    
    
    # apt安装各板指定软件
    
    run_status "apt update" chroot ${PATH_ROOTFS} /bin/bash -c "apt-get update"
    
    mapfile -t packages < <(grep -vE '^#|^$' ${FILE_APT_BASE_BOARD})
    if [[ ${OPT_ROOTFS_TYPE} == "desktop" ]]; then
        mapfile -t desktop_packages  < <(grep -vE '^#|^$' ${FILE_APT_DESKTOP_BOARD})
        packages=("${packages[@]}" "${desktop_packages[@]}")
    fi
    total=${#packages[@]}
    for (( i=0; i<${total}; i++ )); do
        package=${packages[$i]}
        run_status "apt [$((i+1))/${total}] : $package " chroot $PATH_ROOTFS /bin/bash -c "DEBIAN_FRONTEND=noninteractive  apt-get -o Dpkg::Options::='--force-overwrite' install -y ${package}"
        # run_status "board apt [$((i+1))/${total}] : $package " chroot $PATH_ROOTFS /bin/bash -c "DEBIAN_FRONTEND=noninteractive  apt-get install -y -f  ${package}"
    done
    
    run_client_when_successfuly chroot $PATH_ROOTFS /bin/bash -c "DEBIAN_FRONTEND=noninteractive  apt-get clean"
    
    
    cd $PATH_ROOTFS
    umount_chroot $PATH_ROOTFS
    if [ -f "$FILE_ROOTFS_TAR" ]; then
        rm $FILE_ROOTFS_TAR
    fi
    
    run_status "create tar"  tar -czf $FILE_ROOTFS_TAR ./
    # rm -r $PATH_ROOTFS
    
}