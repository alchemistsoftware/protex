module.exports = {
  packagerConfig: {},
  rebuildConfig: {},
  hooks: {
    generateAssets: async (forgeConfig, platform, arch) => {
        // TODO(cjb): Everything you want copied...
    }
  },
  makers: [
    {
      name: '@electron-forge/maker-squirrel',
      config: {},
    },
    {
      name: '@electron-forge/maker-zip',
      platforms: ['linux'],
    },
  ],
};
