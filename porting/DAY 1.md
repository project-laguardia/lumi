# Let's Begin

To start off, the first two objectives are to:
1. Rip `uci` out and replace it with `mgmt`
2. Gain a more in-depth understanding of `luci`'s internals

Goal 1 is a long-term goal. This will likely carry from project to project. Goal 2 is a short-term goal. This will be done by reviewing LuCI's code and rewriting it in a way that is more idiomatic to `mgmt`.

# Hurdle 1: Unraveling the lua spaghetti

LuCI is quite large. She doesn't have the worst spaghetti code, but there is a low level amount of it. We need to identify where Lua binds onto `uci`, so we can begin to rip it out.

I believe the primary `uci` commit lives here: luci/modules/luci-lua-runtime/luasrc/model/uci.lua

Conveniently, `luci` uses a pre-5.2 Lua version, so we can use `module` calls to locate some of the components.

Since C modules expose themselves in a similar way that module does, we can use the string name of each module to locate them both in the Lua code and in the C code.

# Hurdle 2: Understanding the C code

OpenWRT's C code is relatively straightforward and lightweight. However, the build system is a bit of a spaghetti mess (as most low level build systems are). Taking a look around you will notice that a lot of the C code is bundled in directories with some makefiles of extremely consistent structure.

These makefiles are made using the LuCI templates: https://github.com/openwrt/luci/wiki/Modules

These makefiles don't reveal a whole lot about the intended build system. It appears that knowing that the build system is the OpenWRT build system is to be assumed. I did make some doc changes in the wiki to make this more obvious:
- https://github.com/openwrt/luci/wiki/Installation/_history

When reviewing LuCI you may see references to a "buildroot." This seems to be a non-standard, but widely adopted term for wherever you cloned the OpenWRT repository to (the repository itself is effectively the build system). I believe this practice was adopter from OpenWRT's wiki (but I am not sure):
- https://openwrt.org/docs/guide-developer/toolchain/use-buildsystem#details_for_downloading_sources

# Hurdle 3: Scoping OpenWRT's build system down

OpenWRT's build system is quite large and designed primarily for the OpenWRT OS as a whole. I don't believe the entire thing is used by LuCI. I need to narrow down any parts of LuCI/OpenWRT's build system to just what is applicable to building LuMI. Preferably, I need to find something that can be used directly in LuMI without having to rewrite it. From what I've read so far, this may be a possibility, but not guarantee.

If it is possible, I will need to use raw commit links and not head links when I get around to writing a build script that would pull it. This would allow me to offload maintaining said script to OpenWRT while ensuring any changes they make don't immediately propagate and break LuMI (technically, LuMI is out of scope for OpenWRT, so breakage is a significant risk)