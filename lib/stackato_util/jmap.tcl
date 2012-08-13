# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require json::write
package require dictutil ;# get'

# pretty json, all the way.
json::write indented 1
json::write aligned 1

namespace eval ::stackato::jmap {}

# # ## ### ##### ######## ############# #####################
## Convenience commands encapsulating the VMC data structure
## definitions.

proc ::stackato::jmap::manifest {m} {
    map {dict {
	env       array
	staging   {dict {
	    runtime nstring
	}}
	resources dict
	services  array
	uris      narray
	meta      dict
    }} $m
}

proc ::stackato::jmap::nstring {_ s} {
    if {$s eq {}} { return null }
    return [map string $s]
}

proc ::stackato::jmap::narray {t s} {
    if {$s eq {}} { return null }
    if {$s eq "null"} { return null }
    return [map [list array $t] $s]
}

proc ::stackato::jmap::crashed    {c}  { map {array dict} $c }
proc ::stackato::jmap::aliases    {as} { map dict $as }
proc ::stackato::jmap::target     {t}  { map dict $t  }
proc ::stackato::jmap::env        {e}  { map array $e  }
proc ::stackato::jmap::targets    {ts} { map dict $ts }
proc ::stackato::jmap::tgroups    {gs} { map dict $gs }
proc ::stackato::jmap::runtimes   {rs} {
    map {dict {
	* dict
    }} $rs
}
proc ::stackato::jmap::frameworks {fs} { map {dict {* array}} $fs }
proc ::stackato::jmap::resources  {rs} {
    map {array dict} $rs
}

proc ::stackato::jmap::apps    {as} {
    # @todo jmap apps - element type
    map {array {dict {
	env       array
	meta      dict
	resources dict
	services  array
	staging   dict
	uris      array
	services_connect_info {array {dict {
	    tags        array
	    credentials dict
	}}}
    }}} $as
}

proc ::stackato::jmap::user1 {ui} {
    # Note how this contains a copy of appinfo.
    map {dict {
	apps {array {dict {
	    env       array
	    meta      dict
	    resources dict
	    services  array
	    staging   dict
	    uris      array
	    services_connect_info {array {dict {
		tags        array
		credentials dict
	    }}}
	}}}
    }} $ui
}

proc ::stackato::jmap::users {us} {
    map {array {dict {
	apps {array dict}
    }}} $us
}

proc ::stackato::jmap::groups {gs} {
    map {dict {* array}} $gs
}

proc ::stackato::jmap::appinfo {ai} {
    map {dict {
	env       array
	meta      dict
	resources dict
	services  array
	staging   dict
	uris      array
	services_connect_info {array {dict {
	    tags        array
	    credentials dict
	}}}
    }} $ai
}

# services connect info
proc ::stackato::jmap::sci {ai} {
    map {dict {
	tags        array
	credentials dict
    }} $ai
}

# dbshell
proc ::stackato::jmap::dbs {v} {
    map {dict {
	args array
	env  dict
    }} $v
}

proc ::stackato::jmap::stats    {ss} {
    # @todo jmap stats - element type
    map {array {dict {
	stats {dict {
	    usage dict
	    uris array
	}}
    }}} $ss
}

proc ::stackato::jmap::instances {is} {
    # @todo jmap instances - element type
    map {array dict} $is
}

proc ::stackato::jmap::instancemap {is} {
    # @todo jmap instances - element type
    map dict $is
}

proc ::stackato::jmap::service {s} {
    map dict $s
}

proc ::stackato::jmap::services   {ss} {
    # @todo jmap services, fill deeper dicts
    # Descriptions of the *, in order of nesting:
    # - service-type
    # - vendor (name)
    # - version
    # - tier-type
    map {dict {
	system      {dict {
	    * {dict {
		* {dict {
		    * {dict {
			tiers {dict {
			    * {dict {
				options dict
			    }}
			}}
		    }}
		}}
	    }}
	}}
	provisioned {array {dict {
	    meta {dict {
		tags array
	    }}
	}}}
    }} $ss
}

proc ::stackato::jmap::usageinfo {ui} {
    map {dict {
	allocated dict
	usage     dict
    }} $ui
}

proc ::stackato::jmap::clientinfo {ci} {
    map {dict {
	usage  dict
	limits dict
	frameworks {dict {
	    * {dict {
		appservers {array dict}
		runtimes   {array dict}
		detection  {narray dict}
	    }}
	}}
    }} $ci
}

proc ::stackato::jmap::fwinfo {ci} {
    map {dict {
	* {dict {
	    appservers {array dict}
	    runtimes   {array dict}
	    detection  {array dict}
	}}
    }} $ci
}

# # ## ### ##### ######## ############# #####################
## Core - Should go into json::write
## Alt implementation: typecodes = name of helper commands in a namespace.
## => Extensible with user commands => Actually, the commands complex types
## -- would be such user commands.

proc ::stackato::jmap::map {type data} {
    lassign $type type detail
    switch -exact -- $type {
	{} - string {
	    return [json::write string $data]
	}
	array - list {
	    set tmp {}
	    # detail = type of array elements
	    foreach x $data {
		lappend tmp [map $detail $x]
	    }
	    return [json::write array {*}$tmp]
	}
	dict - object {
	    #puts map/==============================
	    #puts map/type
	    #puts |$type|
	    #puts map/data
	    #puts |$data|
	    #puts map/==============================

	    # detail = dict mapping keys to the types of their values.
	    #          un-listed keys default to type of key '*', if
	    #          present, and string otherwise.
	    #checker -scope local exclude badOption
	    set defaulttype [dict get' $detail * {}]
	    set tmp {}
	    dict for {k v} [dict sort $data] {
		set vtype [dict get' $detail $k $defaulttype]
		lappend tmp $k [map $vtype $v]
	    }
	    return [json::write object {*}$tmp]
	}
	default {
	    if {[llength [info commands ::stackato::jmap::$type]]} {
		return [::stackato::jmap::$type $detail $data]
	    }

	    return -code error -errorcode {JSON MAP BAD TYPE} \
		"Bad json map type \"$type\""
	}
    }
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::jmap {
    namespace export map \
	aliases target targets clientinfo runtimes frameworks \
	services apps stats env instances service resources \
	manifest crashed instancemap appinfo sci users dbs \
	user1 fwinfo groups tgroups usageinfo
    namespace ensemble create
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::jmap 0
