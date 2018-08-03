#!/bin/bash

REPO_PATH=/opt/rainbond/install
PKG_PATH=/opt/rainbond/install/install/pkgs
IMG_PATH=/opt/rainbond/install/install/imgs

YAML_PATH=$REPO_PATH/rainbond.yaml.default


which yq 2>&1>/dev/null || (
    curl https://pkg.rainbond.com/releases/common/yq -o /usr/local/bin/yq
    chmod +x /usr/local/bin/yq
)

[ -d "$REPO_PATH" ] || mkdir -p $REPO_PATH

init_repo(){
    git clone --depth 1 -b v3.7 https://github.com/goodrain/rainbond-install.git $REPO_PATH
    [ -d "$PKG_PATH" ] || mkdir -p $PKG_PATH/{debian,centos}
    [ -d "$IMG_PATH" ] || mkdir -p $IMG_PATH
}

debian_pkg(){
    echo "download debian/ubuntu offline package"
    dpkg=$(yq r $YAML_PATH rbd-pkgs.debian | awk '{print $2}')
    common_pkg=$(yq r $YAML_PATH rbd-pkgs.common | awk '{print $2}')
    for pkg in ${dpkg[@]} ${common_pkg[@]}
    do
        apt install ${pkg} -d  2>&1>/dev/null
        cp -a /var/cache/apt/archives/$pkg* $PKG_PATH/debian/
        echo "download debian $pkg ok"
    done
}

centos_pkg(){
    echo "download centos offline package"
    cpkg=$(yq r $YAML_PATH rbd-pkgs.centos | awk '{print $2}')
    common_pkg=$(yq r $YAML_PATH rbd-pkgs.common | awk '{print $2}')
    for pkg in ${cpkg[@]} ${common_pkg[@]}
    do
        yum install ${pkg} --downloadonly --downloaddir=$PKG_PATH/centos/ 2>&1>/dev/null
        ls $PKG_PATH/centos/ | grep "$pkg" 2>&1>/dev/null
        if [ "$?" == 0 ];then
            echo "download centos $pkg ok"
        else
            echo "download centos $pkg failed"
        fi
    done
}

download_pkg(){
    if [ "$1" == "all" ];then
        centos_pkg
        debian_pkg
    elif [ "$1" == "debian" -o "$1" == "ubuntu" ];then
        debian_pkg
    else
        centos_pkg
    fi
}

download_img(){
    rbd_plugins=(mysql rbd-api rbd-dns rbd-registry rbd-repo rbd-worker rbd-eventlog rbd-entrance rbd-chaos rbd-lb rbd-mq rbd-webcli rbd-app-ui rbd-monitor)
    rbd_runtimes=(tcm mesh runner adapter builder pause rbd-cni k8s-cni)
    k8s=(cfssl kubecfg api static manager schedule server calico)
    for Moudles in ${rbd_plugins[@]} ${rbd_runtimes[@]} ${k8s[@]}
    do
        Img=$( yq r $YAML_PATH *.$Moudles.image | grep -v null | awk '{print $2}')
        Ver=$( yq r $YAML_PATH *.$Moudles.version | grep -v null | awk '{print $2}')
        if [  -z "$Img" -o -z "$Ver" ];then
            echo "not found $Moudles, skip..."
            continue
        fi
        Pub_Img=rainbond/$Img:$Ver
        if [ "$Img" == "builder" ];then
            Pri_Img=goodrain.me/$Img
        elif [ "$Img" == "mesh" ];then
            Pri_Img=goodrain.me/$Img:mesh_plugin
        else
            Pri_Img=goodrain.me/$Img:$Ver
        fi

        #echo "$Moudles $Img $Ver $Pub_Img"
        echo "docker pull $Pub_Img"
        docker pull $Pub_Img 2>&1>/dev/null
        docker tag $Pub_Img $Pri_Img 2>&1>/dev/null
        echo "docker save $Pri_Img"
        docker save $Pri_Img | gzip > $IMG_PATH/goodrainme_${Img}_${Ver}.gz
    done
}

offline_tgz(){
    tar zcvf install.v3.7.$(date +%F).tgz /opt/rainbond/install
}

case $1 in
    *)
    init_repo
    download_pkg ${1:-centos}
    download_img ${2:-3.7}
    offline_tgz
    ;;
esac