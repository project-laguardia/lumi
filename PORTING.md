# Hurdle 3: Scoping OpenWRT's Build System Down (Continued)

## Previously:
- https://github.com/project-laguardia/lumi/blob/main/porting/DAY%203.md

> When using the SDK (or the full buildroot), you will often be instructed to use `feeds` quite rigorously mainly for healing your SDK, buildroot, or if you are building using the OS itself, your OpenWRT installation. It can also be used to install dependencies for your project as well.
> ...
> LuCI instructs that you run:
> ```bash
> ./scripts/feeds update
> ./scripts/feeds install -a -p luci
> make menuconfig
> ```
> ...
> (from SDK container > `setup.sh`):
> ```bash
> if [ -z "$PACKAGES" ]; then
> 	# compile all packages in feed
> 	for FEED in $ALL_CUSTOM_FEEDS; do
> 		group "feeds install -p $FEED -f -a"
> 		./scripts/feeds install -p "$FEED" -f -a
> 		endgroup
> 	done
> 
> 	RET=0
> 
> 	make \
> 		BUILD_LOG="$BUILD_LOG" \
> 		CONFIG_SIGNED_PACKAGES="$CONFIG_SIGNED_PACKAGES" \
> 		IGNORE_ERRORS="$IGNORE_ERRORS" \
> 		CONFIG_AUTOREMOVE=y \
> 		V="$V" \
> 		-j "$(nproc)" || RET=$?
> else
> ...
> fi
> ```
> ...
> Now that we understand how they build the packages automatically, we can now use this knowledge for building our own way. For now, we will use the recommended `make menuconfig` as described in Task 1, but we will likely switch to using the GH Actions way of building in the future.

## Task 1: Digesting `./scripts/feeds` (continued)
- https://gitlab.com/openwrt/openwrt/openwrt/-/blob/9ea174c7bf64ec34e96871ce223d7a597ca80d26/scripts/feeds

To continue from where we left off, we will now look at how `./scripts/feeds` works in more detail. The `feeds` system is a way to manage packages and their dependencies in OpenWRT. It allows you to update, install, and manage packages easily.

First thing we'll notice is the used libraries:
```perl
use Getopt::Std;
use FindBin;
use Cwd;
use lib "$FindBin::Bin";
use metadata;
use warnings;
use strict;
use Cwd 'abs_path';
```

All of these are standard Perl libraries, except for `metadata`, which is another part of the OpenWRT build system, and I believe we will need it to learn how the OpenWRT SDK makes config files for menuconfig. For now, we will continue digesting `./scripts/feeds` and come back to it later.

The first thing `feeds` does is setup the working environment and verify make:
```perl

chdir "$FindBin::Bin/..";
$ENV{TOPDIR} //= getcwd();
chdir $ENV{TOPDIR};
$ENV{GIT_CONFIG_PARAMETERS}="'core.autocrlf=false'";
$ENV{GREP_OPTIONS}="";

my $mk=`command -v gmake 2>/dev/null`;	# select the right 'make' program
chomp($mk);		# trim trailing newline
$mk or $mk = "make";	# default to 'make'

# check version of make
my @mkver = split /\s+/, `$mk -v`, 4;
my $valid_mk = 1;
$mkver[0] =~ /^GNU/ or $valid_mk = 0;
$mkver[1] =~ /^Make/ or $valid_mk = 0;

my ($mkv1, $mkv2) = split /\./, $mkver[2];
($mkv1 >= 4 || ($mkv1 == 3 && $mkv2 >= 81)) or $valid_mk = 0;

$valid_mk or die "Unsupported version of make found: $mk\n";
```

Then we are provided with a good handful of different functions:
```perl
sub parse_file($$);
sub parse_config();
sub update_location($$);
sub update_index($);
sub update_feed_via($$$$$$$);
sub get_targets($);
sub get_feed($);
sub get_installed();
sub search_feed;
sub list_feed;
sub do_install_src($$);
sub do_install_target($);
sub lookup_src($$);
sub lookup_package($$);
sub lookup_target($$);
sub is_core_src($);
sub install_target;
sub install_src;
sub install_package;
sub install_target_or_package;
sub refresh_config;
sub uninstall_target($);
sub update_feed($$$$$$);

sub feed_config();
sub search;
sub uninstall;
sub install;
sub list;
sub update;
sub usage();
```

And a few useful hashtables:
```perl
my %update_method = (
	'src-svn' => {
		'init'		=> "svn checkout '%s' '%s'",
		'update'	=> "svn update",
		'controldir'	=> ".svn",
		'revision'	=> "svn info | grep 'Revision' | cut -d ' ' -f 2 | tr -d '\n'"},
	'src-cpy' => {
		'init'		=> "cp -Rf '%s' '%s'",
		'update'	=> "",
		'revision'	=> "echo -n 'local'"},
	'src-link' => {
		'init'		=> "ln -s '%s' '%s'",
		'update'	=> "",
		'revision'	=> "echo -n 'local'"},
	'src-dummy' => {
		'init'		=> "true '%s' && mkdir '%s'",
		'update'	=> "",
		'revision'	=> "echo -n 'dummy'"},
	'src-git' => {
		'init'          => "git clone --depth 1 '%s' '%s'",
		'init_branch'   => "git clone --depth 1 --branch '%s' '%s' '%s'",
		'init_commit'   => "git clone '%s' '%s' && cd '%s' && git checkout -b '%s' '%s' && cd -",
		'update'	=> "git pull --ff-only",
		'update_rebase'	=> "git pull --rebase=merges",
		'update_stash'	=> "git pull --rebase=merges --autostash",
		'update_force'	=> "git pull --ff-only || (git reset --hard HEAD; git pull --ff-only; exit 1)",
		'post_update'	=> "git submodule update --init --recursive",
		'controldir'	=> ".git",
		'revision'	=> "git rev-parse HEAD | tr -d '\n'"},
	'src-git-full' => {
		'init'          => "git clone '%s' '%s'",
		'init_branch'   => "git clone --branch '%s' '%s' '%s'",
		'init_commit'   => "git clone '%s' '%s' && cd '%s' && git checkout -b '%s' '%s' && cd -",
		'update'	=> "git pull --ff-only",
		'update_rebase'	=> "git pull --rebase=merges",
		'update_stash'	=> "git pull --rebase=merges --autostash",
		'update_force'	=> "git pull --ff-only || (git reset --hard HEAD; git pull --ff-only; exit 1)",
		'post_update'	=> "git submodule update --init --recursive",
		'controldir'	=> ".git",
		'revision'	=> "git rev-parse HEAD | tr -d '\n'"},
	'src-gitsvn' => {
		'init'	=> "git svn clone -r HEAD '%s' '%s'",
		'update'	=> "git svn rebase",
		'controldir'	=> ".git",
		'revision'	=> "git rev-parse HEAD | tr -d '\n'"},
	'src-bzr' => {
		'init'		=> "bzr checkout --lightweight '%s' '%s'",
		'update'	=> "bzr update",
		'controldir'	=> ".bzr"},
	'src-hg' => {
		'init'		=> "hg clone '%s' '%s'",
		'update'	=> "hg pull --update",
		'controldir'	=> ".hg"},
	'src-darcs' => {
		'init'    => "darcs get '%s' '%s'",
		'update'  => "darcs pull -a",
		'controldir' => "_darcs"},
);
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
```

Some important things to note about the update methods:
- `src-cpy`, `src-link`, and `src-dummy` are used for local sources that basically do not require any updates.
  - `src-cpy` does, however it is just a copy of an already local resource.
- `src-git`, `src-git-full`, `src-gitsvn`, `src-bzr`, `src-hg`,`src-svn` and `src-darcs` are all used for version control systems.
  - `src-git` is the most common one, and it is used for Git repositories.
  - `src-git-full` is used for full Git repositories, which may include all branches and history.
  - `src-gitsvn` is used for Git repositories that are backed by a Subversion repository.
  - `src-bzr`, `src-hg`, and `src-darcs` are used for Bazaar, Mercurial, and Darcs repositories respectively.
  - `src-svn` is used for Subversion repositories.

We have already gone over introducing the commands, but as a refresher, here they are once more:
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

After some review of `feeds` source code, most of the "installing" is just linking and copying source files to the appropriate directories. Build doesn't actually occur here, so I will have to dig into `make` invocation during `make menuconfig`/`make defconfig` to see how it is done. I suspect that [include/toplevel.mk](https://gitlab.com/openwrt/openwrt/openwrt/-/blob/master/include/toplevel.mk) and [scripts/package-metadata.pl](https://gitlab.com/openwrt/openwrt/openwrt/-/blob/master/scripts/package-metadata.pl) are the two files that actually make the necessary config files for menuconfig. Though, I'm not too sure. OpenWRT's SDK is quite opaque and minimally documented, so it is hard to tell what is actually going on even if you can read the source code.

Before moving on there is one thing I do want to point out. `feeds` has a `refresh_config` function that calls `make defconfig`/`make oldconfig` and that function is called every time the commands `install`, `uninstall`, and `update` are called.

## Task 2: Digesting `make menuconfig`

The menuconfig make target is defined in the "Top Level" Makefile, which is a highly referenced file in the OpenWRT build system.
- `./include/toplevel.mk` is referenced [here](https://gitlab.com/openwrt/openwrt/openwrt/-/blob/9ea174c7bf64ec34e96871ce223d7a597ca80d26/Makefile#L33)
- `./include/toplevel.mk` defines the `menuconfig` target [here](https://gitlab.com/openwrt/openwrt/openwrt/-/blob/master/include/toplevel.mk#L135-140)

This target is really just a wrapper for `./scripts/config/mconf ./Config.in`

`toplevel.mk` is run once every time `make` is called. From the SDK root Makefile, this is ensured using this mechanism:
```makefile
ifneq ($(OPENWRT_BUILD),1)
  override OPENWRT_BUILD=1
  export OPENWRT_BUILD
```
Where `OPENWRT_BUILD` is acting like a flag to indicate that make is already running. Note that at any time during the make process, you can clear `OPENWRT_BUILD` if you want to run `make` inside your build script in a way that it thinks it isn't running. This has a handful of uses across the SD, even inside `./scripts/feeds`:
```perl
sub update_index($)
{
	my $name = shift;

	-d "./feeds/$name.tmp" or mkdir "./feeds/$name.tmp" or return 1;
	-d "./feeds/$name.tmp/info" or mkdir "./feeds/$name.tmp/info" or return 1;

	system("$mk -s prepare-mk OPENWRT_BUILD= TMP_DIR=\"$ENV{TOPDIR}/feeds/$name.tmp\"");
	system("$mk -s -f include/scan.mk IS_TTY=1 SCAN_TARGET=\"packageinfo\" SCAN_DIR=\"feeds/$name\" SCAN_NAME=\"package\" SCAN_DEPTH=5 SCAN_EXTRA=\"\" TMP_DIR=\"$ENV{TOPDIR}/feeds/$name.tmp\"");
	system("$mk -s -f include/scan.mk IS_TTY=1 SCAN_TARGET=\"targetinfo\" SCAN_DIR=\"feeds/$name\" SCAN_NAME=\"target\" SCAN_DEPTH=5 SCAN_EXTRA=\"\" SCAN_MAKEOPTS=\"TARGET_BUILD=1\" TMP_DIR=\"$ENV{TOPDIR}/feeds/$name.tmp\"");
	system("ln -sf $name.tmp/.packageinfo ./feeds/$name.index");
	system("ln -sf $name.tmp/.targetinfo ./feeds/$name.targetindex");

	return 0;
}
```

```perl
sub get_installed() {
	system("$mk -s prepare-tmpinfo OPENWRT_BUILD=");
	clear_packages();
	parse_package_metadata("./tmp/.packageinfo");
	%installed_pkg = %vpackage;
	%installed = %srcpackage;
	%installed_targets = get_targets("./tmp/.targetinfo");
}
```

Now, we need to address how the SDK generates the config files for `menuconfig`. `toplevel.mk` defines another target called `prepare-tmpinfo`. This target invokes the aforementioned `./scripts/package-metadata.pl` script, which is used to generate the `.in` files for `menuconfig`. 

Another interesting discovery is that it may also invoke `./scripts/target-metadata.pl`.

I think this is enough information to start working on porting LuCI now. If there is any questions about what parts of the SDK variables or scripts may refer to, we now have the files for looking them up. One last step for me is to organize my findings and post them in the README.