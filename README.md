# Lumi

A LuCI port from `uci` to `mgmt`.

# Contributing

Contributions are welcome! Please read over the commit rules in [./commitlintrc.yml](./commitlintrc.yaml). We do deviate from Angular's commit rules slightly. Most notably, we deprecate `chore` in favor of `infra` for infrastructure tooling, `meta` for manifest changes like `package.json`, `cargo.toml`, etc., and `devtools` for devtool-writing not covered by `infra`.
- An example change warranting `infra` would be changes to `.github`
- An example change warranting `meta` would be changes to `.gitignore`, `.commitlintrc.yml`, or `package.json`
- An example change warranting `devtools` would be changes to `porting/~search.ps1`

_Scoping is recommended._ At this time, we do _not_ enforce scoping in any manner, but here are some well-known scopes for this project:
- `readme` for changes to the README
- `porting` typically documentation changes made to PORTING.md or to the `porting` directory
- `vcs` for changes to the version control system, such as `.gitignore` or modifying `.commitlintrc.yml`

# Porting

The gitignore is already configured to ignore the `luci` directory. If needed, you can clone `luci` to that location if you need to reference its source or build files.

```pwsh
git clone https://github.com/openwrt/luci ./luci
```

My work with porting will be logged in `PORTING.md` show casing my active work. For archived work, you can see the `porting` directory.

# Building

To read up on how `luci` is built, you can start here (but please reference the OpenWRT SDK section below for more info on how the SDK works):
- wiki: https://github.com/openwrt/luci/wiki
- components: https://github.com/openwrt/luci/wiki/Modules
- build system: https://github.com/openwrt/luci/wiki/Installation

## OpenWRT SDK

LuCI depends on the OpenWRT SDK to build. Fortunately, it is available as a container for Docker and GH Actions. Unlike it has been historically, you don't need to build OpenWRT packages on OpenWRT itself. The following containers allow you to build packages for OpenWRT on any system:

- [https://ghcr.io/openwrt/sdk](https://ghcr.io/openwrt/sdk)
- [openwrt/sdk - Docker Hub](https://hub.docker.com/r/openwrt/sdk)

**NOTE:** The containers and SDK are not well-documented as a whole. I can't teach you everything, but I can cite some useful resources for you that will help you learn:
- About the containers:
  - [GH Actions container source code and guide](https://github.com/openwrt/gh-action-sdk)
  - [Docker container source code and guide](https://github.com/openwrt/docker)
- Important SDK tools:
  - [`./scripts/feeds`](https://gitlab.com/openwrt/openwrt/openwrt/-/blob/9ea174c7bf64ec34e96871ce223d7a597ca80d26/scripts/feeds)
    - A utility to manage OpenWRT "feeds" (repositories of packages). This script does not build packages, but it places them in the correct directories, builds out necessary metadata files, and prepares the build system for building packages.
      - It is important to understand that this both `feeds` and `make menuconfig`/`make defconfig` are required to build LuCI.
  - [`./Makefile`](https://gitlab.com/openwrt/openwrt/openwrt/-/blob/9ea174c7bf64ec34e96871ce223d7a597ca80d26/Makefile) and [`./include/toplevel.mk`](https://gitlab.com/openwrt/openwrt/openwrt/-/blob/9ea174c7bf64ec34e96871ce223d7a597ca80d26/include/toplevel.mk)
    - The main and "Top Level" makefiles for the OpenWRT SDK
    - [`toplevel.mk`](https://gitlab.com/openwrt/openwrt/openwrt/-/blob/9ea174c7bf64ec34e96871ce223d7a597ca80d26/include/toplevel.mk) defines most of your common build targets that you will see referenced almost everywhere:
      - `make menuconfig`
      - `make defconfig`
      - `make oldconfig`
      - `make prepare-tmpinfo`
  - [`make prepare-tmpinfo`](https://gitlab.com/openwrt/openwrt/openwrt/-/blob/9ea174c7bf64ec34e96871ce223d7a597ca80d26/include/toplevel.mk#L78-92)
    - This is a target you will want to be familiar with when dealing with LuCI's makefiles. This target is what parses package makefiles (like LuCI's) to make the necessary metadata files (such as `.config-package.in` and `Config.in`) that are used by `make menuconfig`, `make defconfig`, and `make oldconfig`.