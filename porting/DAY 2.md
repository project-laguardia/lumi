# Hurdle 3: Scoping OpenWRT's Build System Down (Continued)

## Review of What I've Already Done:

Previously:
- https://github.com/project-laguardia/lumi/blob/2d9f32fd69a8b9f94b96052ee88a372a6d962409/porting/DAY%201.md
- https://www.reddit.com/r/linux/comments/1lvz088/planning_a_luci_port_from_uci_to_mgmt_day_1/

> OpenWRT's build system is quite large and designed primarily for the OpenWRT OS as a whole. I don't believe the entire thing is used by LuCI. I need to narrow down any parts of LuCI/OpenWRT's build system to just what is applicable to building LuMI. Preferably, I need to find something that can be used directly in LuMI without having to rewrite it. From what I've read so far, this may be a possibility, but not guarantee.
> 
> If it is possible, I will need to use raw commit links and not head links when I get around to writing a build script that would pull it. This would allow me to offload maintaining said script to OpenWRT while ensuring any changes they make don't immediately propagate and break LuMI (technically, LuMI is out of scope for OpenWRT, so breakage is a significant risk)

- https://github.com/openwrt/luci/wiki/Installation#openwrt-feed
- https://openwrt.org/docs/guide-developer/toolchain/use-buildsystem#details_for_downloading_sources

## Task 1: Digesting `./scripts/feeds` and `./scripts/feeds.conf.default`

- https://gitlab.com/openwrt/openwrt/openwrt/-/blob/master/scripts/feeds
- https://gitlab.com/openwrt/openwrt/openwrt/-/blob/master/scripts/feeds.conf.default

**`./scripts/feeds`**

`feeds` is the main script for OpenWRT's package feed management written in Perl, abstracting all the repository operations and package install/uninstall logic in a uniform manner, so users don't have to worry themselves with details of where packages come from or how they are versioned.

It is designed to make extending or customizing OpenWRT much simpler and safer with community feeds.

**Execution:**

Execution of `feeds` begins at the end of the script:
- https://gitlab.com/openwrt/openwrt/openwrt/-/blob/9ea174c7bf64ec34e96871ce223d7a597ca80d26/scripts/feeds#L942-962

Here we can begin to see the available commands:

```perl
my %commands = (
	'list' => \&list,
	'update' => \&update,
	'install' => \&install,
	'search' => \&search,
	'uninstall' => \&uninstall,
	'feed_config' => \&feed_config,
	'clean' => sub {
		system("rm -rf ./feeds ./package/feeds ./target/linux/feeds");
	}
);

my $arg = shift @ARGV;
$arg or usage();
parse_config;
foreach my $cmd (keys %commands) {
	$arg eq $cmd and do {
		exit(&{$commands{$cmd}}());
	};
}
usage();
```

Here is the usage function:

```perl
sub usage() {
	print <<EOF;
Usage: $0 <command> [options]

Commands:
	list [options]: List feeds, their content and revisions (if installed)
	Options:
	    -n :            List of feed names.
	    -s :            List of feed names and their URL.
	    -r <feedname>:  List packages of specified feed.
	    -d <delimiter>: Use specified delimiter to distinguish rows (default: spaces)
	    -f :            List feeds in opkg feeds.conf compatible format (when using -s).

	install [options] <package>: Install a package
	Options:
	    -a :           Install all packages from all feeds or from the specified feed using the -p option.
	    -p <feedname>: Prefer this feed when installing packages.
	    -d <y|m|n>:    Set default for newly installed packages.
	    -f :           Install will be forced even if the package exists in core OpenWrt (override)

	search [options] <substring>: Search for a package
	Options:
	    -r <feedname>: Only search in this feed

	uninstall -a|<package>: Uninstall a package
	Options:
	    -a :           Uninstalls all packages.

	update -a|<feedname(s)>: Update packages and lists of feeds in feeds.conf .
	Options:
	    -a :           Update all feeds listed within feeds.conf. Otherwise the specified feeds will be updated.
	    -r :           Update by rebase. (git only. Useful if local commits exist)
	    -s :           Update by rebase and autostash. (git only. Useful if local commits and uncommited changes exist)
	    -i :           Recreate the index only. No feed update from repository is performed.
	    -f :           Force updating feeds even if there are changed, uncommitted files.

	clean:             Remove downloaded/generated files.

EOF
	exit(1);
}
```

We are going to put a pause on this and come back to it later. This `feeds` script is only used twice, but appears to be part of the process of setting opkg up and possibly env vars for `make menuconfig`.

## A New Approach: Using their GH Actions to Figure Out How LuCI is Built

I've just realized that another way to approach this is to look at their GH Actions. Upon inspection, it appears that they do have a build flow used to test LuCI, and we even have some example runs to look at:
- https://github.com/openwrt/luci/actions/runs/16175625552/job/45659939315
- https://github.com/openwrt/gh-action-sdk

It appears they use openwrt/gh-action-sdk with a few env vars:
- `ARCH` - `<arch>-<branch>`
- `FEEDNAME` - `packages_ci`
- `V` - `s` - Not sure what this is yet

All of the acceptable env vars are listed here:
- https://github.com/openwrt/gh-action-sdk?tab=readme-ov-file#environmental-variables

We might even be able to use this with `act` to build LuMI locally.

**Digging into `openwrt/gh-action-sdk`**
- https://github.com/openwrt/gh-action-sdk/blob/b8cc97d1072dedff455e2945a73fc43f5c7e1749/action.yml

The bulk of the action is in these lines:
- https://github.com/openwrt/gh-action-sdk/blob/b8cc97d1072dedff455e2945a73fc43f5c7e1749/action.yml#L37C9-L52C14

```bash
docker run --rm \
  --env BUILD_LOG \
  --env EXTRA_FEEDS \
  --env FEEDNAME \
  --env IGNORE_ERRORS \
  --env KEY_BUILD \
  --env PRIVATE_KEY \
  --env NO_DEFAULT_FEEDS \
  --env NO_REFRESH_CHECK \
  --env NO_SHFMT_CHECK \
  --env PACKAGES \
  --env INDEX \
  --env V \
  -v ${{ steps.inputs.outputs.artifacts_dir }}:/artifacts \
  -v ${{ steps.inputs.outputs.feed_dir }}:/feed \
  sdk
```

NOTE: `sdk` is short for `sdk:latest`, which is locally built below:

Where `steps.inputs.outputs.<xxxx>` is an environment variable of the same name both defaulted to `$GITHUB_WORKSPACE` (which is the root of the repository).

The image is built in these steps:
```yaml
# the following 2 steps are noteworthy as they allow us to build the image on other architectures
- name: Set up Docker QEMU
  uses: docker/setup-qemu-action@v3
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3

# the actual build step
- name: Build Docker container image
  uses: docker/build-push-action@v6
  env:
  DOCKER_BUILD_SUMMARY: false
  with:
  push: false
  tags: sdk # sdk:latest
  context: ${{ github.action_path }}
  build-args: |
    CONTAINER
    ARCH
  cache-to: type=gha,mode=max,scope=${{ env.CONTAINER }}-${{ env.ARCH }}
  cache-from: type=gha,scope=${{ env.CONTAINER }}-${{ env.ARCH }}
  load: true
```

**The Dockerfiles**
- https://github.com/openwrt/gh-action-sdk/blob/main/Dockerfile

This Dockerfile is short and is just a wrapper for:
- https://ghcr.io/openwrt/sdk

Checking the [manifest](https://github.com/openwrt/docker/pkgs/container/sdk/454860695?tag=x86_64), we can see that the images are developed [here](https://github.com/openwrt/docker) under the name "Docker containers of the ImageBuilder and SDK."

The actual Dockerfile for the SDK lives here:
- https://github.com/openwrt/docker/blob/4cb14fd55889136f2edb9dda81e38b0e7653c3b3/Dockerfile
  - entrypoint: https://github.com/openwrt/docker/blob/main/setup.sh
  - base image: ghcr.io/openwrt/buildbot/buildworker

The entrypoint just downloads and unpacks the following URL:
- `https://downloads.openwrt.org/<version-path="snapshots|releases/<version-number>">/targets/<arch>/openwrt-<imagebuilder|sdk>-<version>-*.tar.xz`

NOTE: `setup.sh` entrypoint builds imagebuilder by default. If you look at their publishing GH action, you will see the correct `DOWNLOAD_FILE` env var you need for the SDK:
- https://github.com/openwrt/docker/blob/4cb14fd55889136f2edb9dda81e38b0e7653c3b3/.github/workflows/containers.yml#L352C27-L352C59

NOTE: `DOWNLOAD_FILE` is a grep pattern. It should match one of the patterns described by the SDK:
- https://openwrt.org/docs/guide-developer/toolchain/using_the_sdk#downloads

I could not find a public package for buildbot, but I don't think its, because it is not open source. I think they just don't want people using it directly. I believe the source code for it is available here:
- https://github.com/openwrt/buildbot

I believe the spefici buildbot used is this one:
- https://github.com/openwrt/buildbot/blob/main/docker/buildworker/Dockerfile

Now, I don't believe we need to dig further down into the docker images than this. This is probably further than we needed to go anyhow.

However, if we later decide to use a different build system, we can revisit this point and go back and find what we need to replace.

For now, we dive into the SDK:

**The SDK**
- https://openwrt.org/docs/guide-developer/toolchain/using_the_sdk#downloads

Now the link above only hosts pre-built SDKs. The wiki mentions that the SDK can be built from source, but fails to mention where the source is located. It wasn't until downloading it do you get a description of the source from the README:

> This is the OpenWrt SDK. _It contains a stripped-down version of
> the buildroot._ You can use it to test/develop packages without
> having to compile your own toolchain or any of the libraries
> included with OpenWrt.
> 
> To use it, just put your buildroot-compatible package directory
> (including its dependencies) in the subdir 'package/' and run
> 'make' from this directory.
> 
> To make dependency handling easier, you can use ./scripts/feeds
> to install any core package that you need

So the SDK, buildroot, build system, and the OpenWRT repository are all synonymous. The OpenWRT wiki could really use some work to clarify this, so users don't have to dig prepackaged archives to find this out...
- EDIT: I made said changes to both the OpenWRT and LuCI wikis:
  - https://github.com/openwrt/luci/wiki/Installation/_compare/679aa36065801444c8bc6e99ea9251835ece7714...145d4ec133648a3b6f1424c0a075dd8dca0cb079
  - https://github.com/openwrt/luci/wiki/Source-Code/_compare/adfe036e60fb837720c54c13867c1cb63d33626d...b1a59d68b39bf469445e48800fea6e233f67fa4e
  - https://openwrt.org/docs/guide-developer/toolchain/using_the_sdk?do=revisions

Now we can return back to discussing the `feeds` script, but I will do that later. Gonna take a break for now...
