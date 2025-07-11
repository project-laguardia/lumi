# Hurdle 3: Scoping OpenWRT's Build System Down (Continued)

## Previously:
- https://github.com/project-laguardia/lumi/blob/92ec839f81b08e7dab9e785dd73dc0fb5b2b27f7/porting/DAY%202.md

> **`./scripts/feeds`**
> 
> `feeds` is the main script for OpenWRT's package feed management written in Perl, abstracting all the repository operations and package install/uninstall logic in a uniform manner, so users don't have to worry themselves with details of where packages come from or how they are versioned.
>
> ...
> 
> (About understanding their build system:) I've just realized that another way to approach this is to look at their GH Actions. Upon inspection, it appears that they do have a build flow used to test LuCI, and we even have some example runs to look at

## Task 1: Digesting `./scripts/feeds` and `./scripts/feeds.conf.default`

Previously, I failed to mention why we are going over `feeds` and `feeds.conf.default`. When using the SDK (or the full buildroot), you will often be instructed to use `feeds` quite rigorously mainly for healing your SDK, buildroot, or if you are building using the OS itself, your OpenWRT installation. It can also be used to install dependencies for your project as well.

Some, but not all instances of it being referenced in OpenWRT/LuCI documentation:
- https://openwrt.org/docs/guide-developer/toolchain/using_the_sdk
- https://github.com/openwrt/luci/wiki/Installation

LuCI instructs that you run:
```bash
./scripts/feeds update
./scripts/feeds install -a -p luci
make menuconfig
```

...but as we have discovered previously, it may be better for us to use feeds the way their GH Actions do

## Task 2: Reviewing SDK Usage in GH Actions:

LuCI's interaction with the SDK at the workflow level is quite minimal:
- https://github.com/openwrt/luci/blob/4678d6a82c5c36626edb88cdfb93edbb7e93e0fa/.github/workflows/build.yml#L52-L68

```yaml
- name: Build
  uses: openwrt/gh-action-sdk@v7
  env:
    ARCH: ${{ matrix.arch }}-${{ env.BRANCH }}
    FEEDNAME: packages_ci
    V: s

# nothing actually happens between invoking the SDK and moving the packages around:
- name: Move created packages to project dir
  run: cp bin/packages/${{ matrix.arch }}/packages_ci/* . || true
```

It seems that most of the building is done automatically by the SDK action:
- https://github.com/openwrt/gh-action-sdk/blob/b8cc97d1072dedff455e2945a73fc43f5c7e1749/entrypoint.sh

The available environment variables are documented here:
- https://github.com/openwrt/gh-action-sdk/tree/main?tab=readme-ov-file#environmental-variables

> - `ARCH` determines the used OpenWRT SDK Docker container. E.g. `x86_64` or `x86_64-22.03.2`
> - `ARTIFACTS_DIR` determines where the built packages and build logs are saved. Defaults to the default working directory (`GITHUB_WORKSPACE`).
> - `BUILD_LOG` stores the build logs in `./logs`.
> - `CONTAINER` can set other SDK containers than `openwrt/sdk`
> - `EXTRA_FEEDS` are added to the `feeds.conf`, where `|` are replaced by white spaces.
> - `FEED_DIR` used in the created `feeds.conf` for the current repo. Defaults to the default working directory (`GITHUB_WORKSPACE`).
> - `FEEDNAME` is used in the created `feeds.conf` for the current repo. Defaults to `action`.
> - `IGNORE_ERRORS` can ignore failing package builds.
> - `INDEX` makes the action build the package index. Default is 0. Set to 1 to enable.
> - `KEY_BUILD` can be a private Signify/`usign` key to sign the packages (ipk) feed.
> - `PRIVATE_KEY` can be a private key to sign the packages (apk) feed.
> - `NO_DEFAULT_FEEDS` disable adding the default SDK feeds
> - `NO_REFRESH_CHECK` disable check if patches need a refresh
> - `NO_SHFMT_CHECK` disable check if init files are formatted
> - `PACKAGES` (Optional) specify the list of packages (space separated) to be built
> - `V` changes the build verbosity level.

**`setup.sh` Breakdown:**
First, it calls [setup.sh from ghcr.io/openwrt/sdk](https://github.com/openwrt/docker/blob/main/setup.sh)

```bash
group "bash setup.sh"
# snapshot containers don't ship with the SDK to save bandwidth
# run setup.sh to download and extract the SDK
[ ! -f setup.sh ] || bash setup.sh
endgroup
```

Then, it sets up the feed configuration:
```bash
FEEDNAME="${FEEDNAME:-action}"
...
echo "src-link $FEEDNAME /feed/" >> feeds.conf
```

Which we know [from before](https://github.com/project-laguardia/lumi/blob/92ec839f81b08e7dab9e785dd73dc0fb5b2b27f7/porting/DAY%202.md) is `packages_ci`:
> It appears they use openwrt/gh-action-sdk with a few env vars:
> - `ARCH` - `<arch>-<branch>`
> - `FEEDNAME` - `packages_ci`

Noteworthy (but unused by LuCI) is the fact that you can optionally disable the default feeds:
```bash
if [ -z "$NO_DEFAULT_FEEDS" ]; then
	sed \
		-e 's,https://git.openwrt.org/feed/,https://github.com/openwrt/,' \
		-e 's,https://git.openwrt.org/openwrt/,https://github.com/openwrt/,' \
		-e 's,https://git.openwrt.org/project/,https://github.com/openwrt/,' \
		feeds.conf.default > feeds.conf
fi
```

Then the script starts adding in the extra feeds:
```bash
ALL_CUSTOM_FEEDS="$FEEDNAME "
#shellcheck disable=SC2153
for EXTRA_FEED in $EXTRA_FEEDS; do
	echo "$EXTRA_FEED" | tr '|' ' ' >> feeds.conf
	ALL_CUSTOM_FEEDS+="$(echo "$EXTRA_FEED" | cut -d'|' -f2) "
done
```

Finally, it updates the feeds:
```bash
group "feeds.conf"
cat feeds.conf
endgroup

group "feeds update -a"
./scripts/feeds update -a
endgroup
```

Then it builds `defconfig`:
```bash
group "make defconfig"
make defconfig
endgroup
```

We're not gonna go over defconfig, unless I later determine we need it, but more on it can be found here:
- https://gitlab.com/openwrt/openwrt/openwrt/-/blob/master/include/toplevel.mk#L120-124
- It is a makefile target that generates a `.config` file used in kconfig build systems.
- It is used in place of `make menuconfig` to generate a default configuration file for the build system.

The majority of the rest of the script is determined by whether `$PACKAGES` is set or not. LuCI does not set it, so it uses the default behavior:
```bash
if [ -z "$PACKAGES" ]; then
	# compile all packages in feed
	for FEED in $ALL_CUSTOM_FEEDS; do
		group "feeds install -p $FEED -f -a"
		./scripts/feeds install -p "$FEED" -f -a
		endgroup
	done

	RET=0

	make \
		BUILD_LOG="$BUILD_LOG" \
		CONFIG_SIGNED_PACKAGES="$CONFIG_SIGNED_PACKAGES" \
		IGNORE_ERRORS="$IGNORE_ERRORS" \
		CONFIG_AUTOREMOVE=y \
		V="$V" \
		-j "$(nproc)" || RET=$?
else
...
fi
```

Then it wraps up the build:
```bash
if [ "$INDEX" = '1' ];then
	group "make package/index"
	make package/index
	endgroup
fi

if [ -d bin/ ]; then
	mv bin/ /artifacts/
fi

if [ -d logs/ ]; then
	mv logs/ /artifacts/
fi

exit "$RET"
```

Now that we understand how they build the packages automatically, we can now use this knowledge for building our own way. For now, we will use the recommended `make menuconfig` as described in Task 1, but we will likely switch to using the GH Actions way of building in the future.

I think the next 2 steps is to finish digesting `feeds`, then play around with `make menuconfig` to get a better understanding of the available options.