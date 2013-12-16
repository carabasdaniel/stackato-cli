## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Service Instances
## Dependency: config @client, current space.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require cmdr::validate ;# Fail utility command.
package require stackato::mgr::client;# pulls v2 also
package require stackato::validate::common

debug level  validate/serviceauthtoken
debug prefix validate/serviceauthtoken {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export serviceauthtoken
    namespace ensemble create
}

namespace eval ::stackato::validate::serviceauthtoken {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::fail
    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::v2
}

proc ::stackato::validate::serviceauthtoken::default  {p}   { return {} }
proc ::stackato::validate::serviceauthtoken::release  {p x} { return }
proc ::stackato::validate::serviceauthtoken::complete {p x} {
    refresh-client $p
    complete-enum [struct::list map [v2 service_auth_token list] [lambda o {
	$o @name
    }]] 0 $x
}

proc ::stackato::validate::serviceauthtoken::validate {p x} {
    debug.validate/serviceauthtoken {}

    refresh-client $p

    # Note: The auth token list is not cached. Multiple round trips
    # are made when validating multiple tokens.
    set matches [struct::list filter [v2 service_auth_token list 1] [lambda {x o} {
	string equal $x	[$o @name]
    } $x]]
    if {[llength $matches] == 1} {
	debug.validate/serviceauthtoken {OK/canon = $x}
	return [lindex $matches 0]
    }
    debug.validate/serviceauthtoken {FAIL}
    fail $p SERVICEAUTHTOKEN "a service auth token label name" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::serviceauthtoken 0
