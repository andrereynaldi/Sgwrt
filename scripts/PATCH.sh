#!/bin/bash

. ./scripts/INCLUDE.sh


# Initialize environment
init_environment() {
    log "INFO" "Start Builder Patch!"
    log "INFO" "Current Path: $PWD"
    
    cd $GITHUB_WORKSPACE/$WORKING_DIR || error "Failed to change directory"
}

# Apply distribution-specific patches
apply_distro_patches() {
    if [[ "${BASE}" == "openwrt" ]]; then
        log "INFO" "Applying OpenWrt specific patches"
    elif [[ "${BASE}" == "immortalwrt" ]]; then
        log "INFO" "Applying ImmortalWrt specific patches"
        # Remove redundant default packages
        sed -i "/luci-app-cpufreq/d" include/target.mk
    else
        log "INFO" "Unknown distribution: ${BASE}"
    fi
}

# Patch package signature checking
patch_signature_check() {
    log "INFO" "Disabling package signature checking"
    sed -i '\|option check_signature| s|^|#|' repositories.conf
}

# Patch Makefile for package installation
patch_makefile() {
    log "INFO" "Patching Makefile for force package installation"
    sed -i "s/install \$(BUILD_PACKAGES)/install \$(BUILD_PACKAGES) --force-overwrite --force-downgrade/" Makefile
}

# Configure partition sizes
configure_partitions() {
    log "INFO" "Configuring partition sizes"
    # Set kernel and rootfs partition sizes
    sed -i "s/CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=128/" .config
    sed -i "s/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=1024/" .config
}

# Apply Amlogic-specific configurations
configure_amlogic() {
    if [[ "${TYPE}" == "OPHUB" || "${TYPE}" == "ULO" ]]; then    
        sed -i "s|CONFIG_TARGET_ROOTFS_CPIOGZ=.*|# CONFIG_TARGET_ROOTFS_CPIOGZ is not set|g" .config
        sed -i "s|CONFIG_TARGET_ROOTFS_EXT4FS=.*|# CONFIG_TARGET_ROOTFS_EXT4FS is not set|g" .config
        sed -i "s|CONFIG_TARGET_ROOTFS_SQUASHFS=.*|# CONFIG_TARGET_ROOTFS_SQUASHFS is not set|g" .config
        sed -i "s|CONFIG_TARGET_IMAGES_GZIP=.*|# CONFIG_TARGET_IMAGES_GZIP is not set|g" .config
    else
        # Jika tipe lain, hanya tampilkan informasi
        log "INFO" "system type: ${TYPE}"
    fi
}

# apply x86_64
configure_x86_64() {
    if [[ "${ARCH_2}" == "x86_64" ]]; then
        log "INFO" "Applying x86_64 configurations"
        # Disable ISO images generation
        sed -i "s/CONFIG_ISO_IMAGES=y/# CONFIG_ISO_IMAGES is not set/" .config
        # Disable VHDX images generation
        sed -i "s/CONFIG_VHDX_IMAGES=y/# CONFIG_VHDX_IMAGES is not set/" .config
    fi
}

# apply x86_generic
configure_x86_generic() {
    if [[ "${ARCH_2}" == "i386" ]]; then
        log "INFO" "Applying x86_generic configurations"
        
        # Disable problematic image formats for older x86
        sed -i "s/CONFIG_ISO_IMAGES=y/# CONFIG_ISO_IMAGES is not set/" .config
        sed -i "s/CONFIG_VHDX_IMAGES=y/# CONFIG_VHDX_IMAGES is not set/" .config
        sed -i "s/CONFIG_VDI_IMAGES=y/# CONFIG_VDI_IMAGES is not set/" .config
        sed -i "s/CONFIG_VMDK_IMAGES=y/# CONFIG_VMDK_IMAGES is not set/" .config
        
        # Enable basic rootfs formats
        sed -i "s/# CONFIG_TARGET_ROOTFS_EXT4FS is not set/CONFIG_TARGET_ROOTFS_EXT4FS=y/" .config
        sed -i "s/# CONFIG_TARGET_ROOTFS_SQUASHFS is not set/CONFIG_TARGET_ROOTFS_SQUASHFS=y/" .config
        
        # Disable problematic features for generic x86
        sed -i "s/CONFIG_ALL_KMODS=y/# CONFIG_ALL_KMODS is not set/" .config
        sed -i "s/CONFIG_ALL_NONSHARED=y/# CONFIG_ALL_NONSHARED is not set/" .config
        
        # Use legacy x86 configurations
        sed -i "s/CONFIG_TARGET_x86_64=y/# CONFIG_TARGET_x86_64 is not set/" .config
        sed -i "s/# CONFIG_TARGET_x86_generic is not set/CONFIG_TARGET_x86_generic=y/" .config
        
        log "INFO" "x86_generic configurations applied"
    fi
}

# apply raspi 1
configure_raspi1() {
    if [[ "${ARCH_2}" == "arm" ]]; then
        log "INFO" "Applying Raspberry Pi 1 configurations"        
        # Disable x86-specific image formats
        sed -i "s/CONFIG_ISO_IMAGES=y/# CONFIG_ISO_IMAGES is not set/" .config
        sed -i "s/CONFIG_VHDX_IMAGES=y/# CONFIG_VHDX_IMAGES is not set/" .config
        sed -i "s/CONFIG_VDI_IMAGES=y/# CONFIG_VDI_IMAGES is not set/" .config
        sed -i "s/CONFIG_VMDK_IMAGES=y/# CONFIG_VMDK_IMAGES is not set/" .config
        
        # Enable basic rootfs formats
        sed -i "s/# CONFIG_TARGET_ROOTFS_EXT4FS is not set/CONFIG_TARGET_ROOTFS_EXT4FS=y/" .config
        sed -i "s/# CONFIG_TARGET_ROOTFS_SQUASHFS is not set/CONFIG_TARGET_ROOTFS_SQUASHFS=y/" .config
        
        # Reduce build complexity
        sed -i "s/CONFIG_ALL_KMODS=y/# CONFIG_ALL_KMODS is not set/" .config
        
        log "INFO" "Raspberry Pi 1 configurations applied"
    fi
}

# Main execution
main() {
    init_environment
    apply_distro_patches
    patch_signature_check
    patch_makefile
    configure_partitions
    configure_amlogic
    configure_x86_64
    configure_x86_generic
    configure_raspi1
    log "INFO" "Builder patch completed successfully!"
}

# Execute main function
main
