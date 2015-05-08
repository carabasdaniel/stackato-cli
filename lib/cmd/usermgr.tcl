# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. User management.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require dictutil
package require cmdr::ask
package require cmdr::color
package require stackato::cmd::admin
package require stackato::cmd::cgroup
package require stackato::cmd::groups
package require stackato::cmd::orgs
package require stackato::client
package require stackato::jmap
package require stackato::log
package require stackato::mgr::app
package require stackato::mgr::auth
package require stackato::mgr::cgroup
package require stackato::mgr::client
package require stackato::mgr::context
package require stackato::mgr::corg
package require stackato::mgr::cspace
package require stackato::mgr::ctarget
package require stackato::mgr::exit
package require stackato::mgr::service
package require stackato::mgr::tadjunct
package require stackato::mgr::targets
package require stackato::misc
package require stackato::validate::orgname
package require stackato::validate::spacename
package require stackato::validate::username
package require stackato::v2
package require table
package require textutil::adjust

debug level  cmd/usermgr
debug prefix cmd/usermgr {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export usermgr
    namespace ensemble create
}
namespace eval ::stackato::cmd::usermgr {
    namespace export \
	add delete list login logout password who info \
	link-org link-space unlink-org unlink-space \
	token decode-token login-fields delete-by-uuid \
	org-list space-list
    namespace ensemble create

    namespace import ::cmdr::ask
    namespace import ::cmdr::color
    namespace import ::stackato::cmd::admin
    namespace import ::stackato::cmd::cgroup
    rename cgroup cgroupcmd

    namespace import ::stackato::cmd::groups
    namespace import ::stackato::cmd::orgs
    namespace import ::stackato::jmap
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::log::say

    namespace import ::stackato::log::epoch-of
    namespace import ::stackato::log::since
    namespace import ::stackato::log::pretty-since

    namespace import ::stackato::mgr::app
    namespace import ::stackato::mgr::auth
    namespace import ::stackato::mgr::cgroup
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::context
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::mgr::exit
    namespace import ::stackato::mgr::service
    namespace import ::stackato::mgr::tadjunct
    namespace import ::stackato::mgr::targets
    namespace import ::stackato::misc
    namespace import ::stackato::validate::orgname
    namespace import ::stackato::validate::spacename
    namespace import ::stackato::validate::username
    namespace import ::stackato::v2
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::usermgr::link-org {config} {
    debug.cmd/usermgr {}

    set theuser [$config @user]
    set theorg  [$config @org]

    # Always link developer role. This goes beyond developer as
    # default, it happens even when other roles are specified.
    $config @developer set yes

    foreach def [OrgRoles $config] {
	lassign $def attru attro label
	display "Adding user [$theuser @name] to [$theorg @name], as $label ... " false

	# NOTE: While semantically equivalent in the final result
	# these two operations have different permissions when it
	# comes to non-admin users. The disabled form is restricted to
	# full-blown admins, whereas the other, active code, works for
	# any org-manager

	#$theuser $attru add $theorg
	$theorg  $attro add $theuser

	display [color good OK]
    }
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::usermgr::link-space {config} {
    debug.cmd/usermgr {}

    set theuser  [$config @user]
    set thespace [$config @space]

    foreach def [SpaceRoles $config] {
	lassign $def attru attrs label
	display "Adding user [$theuser @name] to [$thespace @name], as $label ... " false

	# NOTE: See link-org for the details.

	#$theuser  $attru add $thespace
	$thespace $attrs add $theuser

	display [color good OK]
    }
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::usermgr::unlink-org {config} {
    debug.cmd/usermgr {}

    set theuser [$config @user]
    set theorg  [$config @org]

    SetRolesForUnlink $config
    foreach def [lreverse [OrgRoles $config]] {
	lassign $def attru attro label
	display "Removing $label [$theuser @name] from [$theorg @name] ... " false

	# NOTE: See link-org for the details.

	#$theuser $attru remove $theorg
	$theorg  $attro remove $theuser

	display [color good OK]
    }
    return
}

proc ::stackato::cmd::usermgr::unlink-space {config} {
    debug.cmd/usermgr {}

    set theuser  [$config @user]
    set thespace [$config @space]

    foreach def [SpaceRoles $config] {
	lassign $def attru attrs label
	display "Removing $label [$theuser @name] from [$thespace @name] ... " false

	# NOTE: See link-org for the details.

	#$theuser  $attru remove $thespace
	$thespace $attrs remove $theuser

	display [color good OK]
    }
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::usermgr::SetRolesForUnlink {config} {
    set roles {@manager @billing @auditor}
    # Check if any of the special roles is requested. If yes, only
    # these are handled.
    foreach r $roles {
	# Ignore unknown parameter (billing, for space)
	if {![$config has $r]} continue
	# Any special role is set => no default @developer, no expansion
	if {[$config $r]} return
    }
    # None of the special roles is set.
    # @developer becomes default, and forces all others as well.
    $config @developer set yes
    foreach r $roles {
	$config $r set yes
    }
    return
}

proc ::stackato::cmd::usermgr::OrgRoles {config} {
    return [Roles $config {
	@developer {@organizations                 @users            User}
	@manager   {@managed_organizations         @managers         Manager}
	@billing   {@billing_managed_organizations @billing_managers Billing-Manager}
	@auditor   {@audited_organizations         @auditors         Auditor}
    }]
}

proc ::stackato::cmd::usermgr::SpaceRoles {config} {
    return [Roles $config {
	@developer {@spaces         @developers Developer}
	@manager   {@managed_spaces @managers   Manager}
	@auditor   {@audited_spaces @auditors   Auditor}
    }]
}

proc ::stackato::cmd::usermgr::Roles {config def} {
    set result {}
    foreach {r a} $def {
	if {![$config $r]} continue
	lappend result $a
    }
    # None is set, use @developer as the default.
    if {![llength $result]} {
	lappend result [dict get $def @developer]
    }
    return $result
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::usermgr::add {config} {
    debug.cmd/usermgr {}

    set promptok [cmdr interactive?]

    set client [$config @client]
    # logged in    - not necessarily (first setup)
    # we are admin - ditto

    set username [$config @name]
    # Implied interaction. Can be disabled.

    set email [$config @email]
    if {[$client isv2] && ![$config @email set?]} {
	if {$promptok} {
	    set email [ask string "Email: "]
	}
    }

    set password [$config @password] ;# default: empty
    if {![$config @password set?]} {
	if {$promptok} {
	    set password  [ask string* "Password: "]
	    set password2 [ask string* "Verify Password: "]
	    if {$password ne $password2} {
		err "Passwords did not match, try again"
	    }
	}
    }

    if {$username eq {}} {
	err "Need a valid [expr {[$client isv2] ? "user-name" : "email"}]"
    }

    if {[$client isv2] && ($email eq {})} {
	err "Need a valid --email"
    }

    if {$password eq {}} {
	err "Need a password"
    }

    # Create user, first with the UAA, then the CC.
    display {Creating New User ... } false

    if {[$client isv2]} {
	display ""

	# Optional parts of the user definition.
	set given  [$config @given]
	set family [$config @family]

	set theuser [v2 user new]
	set doadmin [$theuser create! $username $email \
			 $given $family $password \
			 [$config @admin]]
	# implied commit
    } else {
	set doadmin [$config @admin]
	$client add_user $username $password
	set theuser $username ;# for grant-core
    }
    display [color good OK]

    # # ## ### Check and process group-specific information.

    # I. Add user to a specific group (v1), or organization (v2)
    if {[$config @group set?]} {
	set group [$config @group]

	groups add-user-core $client $group $email
    }

    if {[$client isv2]} {
	if {[$config @no-organization]} {
	    display [color warning "The new user is kept out of all organizations."]
	} else {
	    set org [$config @organization]

	    display "Adding new user to [$org @name] ..."

	    display "  as user ..."
	    $theuser @organizations         add $org

	    if {[$config @manager]} {
		display "  as manager ..."
		$theuser @managed_organizations add $org
	    }
	    if {[$config @auditor]} {
		display "  as auditor ..."
		$theuser @audited_organizations add $org
	    }

	    display [color warning OK]
	}
    }

    # II. Apply limits to the user (as group)
    if {
	[$config @apps     set?] ||
	[$config @appuris  set?] ||
	[$config @services set?] ||
	[$config @sudo     set?] ||
	[$config @drains   set?] ||
	[$config @mem      set?]
    } {
	groups limits-core $client $email $config
    }

    # # ## ### Done with group-specific information

    if {$doadmin} {
	# Make the user an admin also
	admin grant-core $client $theuser
	# NOTE: add-user: Even if this fails, the user
	# NOTE: add-user: exists, just not as admin.
	# NOTE: add-user: Should we possibly roll back?
    }

    if {[auth get] ne {}} return
    # if we are not logged in for the current target, log in as the
    # new user

    login $config
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::usermgr::delete-by-uuid {config} {
    set client [$config @client]
    set uuid   [$config @uuid]

    try {
	display "Deleting in AOK: $uuid ... " false
	$client uaa_delete_user $uuid
    } on error {e o} {
	display [color bad "ERR: $e"]
    } on ok {e o} {
	display [color good OK]
    }

    try {
	display "Deleting in CC:  $uuid ... " false
	$client delete-by-url /v2/users/$uuid
    } on error {e o} {
	display [color bad "ERR: $e"]
    } on ok {e o} {
	display [color good OK]
    }

    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::usermgr::delete {config} {
    debug.cmd/usermgr {}

    set client [$config @client]
    # logged in    - not necessarily (first setup)
    # we are admin - ditto

    if {[$client isv2]} {
	DeleteV2 $config $client
    } else {
	DeleteV1 $config $client
    }
}

proc ::stackato::cmd::usermgr::DeleteV2 {config client} {
    set theuser  [$config @email]

    # NOTE / TODO ? Under v2 apps belong to spaces, not specific users, I believe. Deleting the user should not affect applications and services.
    # But what about org and spaces when a owning user? is deleted.

    display {Deleting User ... } false

    if {[$theuser email] eq [$client current_user_mail]} {
	err "Forbidden to delete the currently logged-in user"
    }

    $theuser delete!
    # implied commit
    display [color good OK]
    return
}

proc ::stackato::cmd::usermgr::DeleteV1 {config client} {
    set email    [$config @email]
    set promptok [cmdr interactive?]

    # Check to make sure all apps and services are deleted before
    # deleting the user. implicit proxying.

    $client proxy_for $email
    try {
	set apps [$client apps]
	if {[llength $apps]} {
	    # Why is this not outside? This way if there are services,
	    # but no apps, no question is asked.
	    if {$promptok} {
		set proceed \
		    [ask yn \
			 "\nDeployed applications and associated services will be DELETED, continue ? " \
			 no]
		if {!$proceed} {
		    err "Aborted" 
		}
	    }

	    foreach a $apps {
		app delete $config $client [dict getit $a name] 1
	    }
	}

	foreach s [$client services] {
	    service delete-with-banner $client [dict getit $s name]
	}
    } finally {
	# Reset proxying
	$client proxy= {}
    }

    display {Deleting User ... } false
    $client delete_user $email
    display [color good OK]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::usermgr::org-list {config} {
    debug.cmd/usermgr {}

    set theorg [corg get]

    set usr [join [lsort -dict [$theorg @users            the_name]] \n]
    set mgr [join [lsort -dict [$theorg @managers         the_name]] \n]
    set bil [join [lsort -dict [$theorg @billing_managers the_name]] \n]
    set aud [join [lsort -dict [$theorg @auditors         the_name]] \n]

    if {[$config @json]} {
	display [jmap map {dict {* array}} \
		     [dict create \
			  user            $usr \
			  manager         $mgr \
			  billing-manager $bil \
			  auditor         $aud]]
	return
    }

    display "Organization [$theorg @name] ..."
    [table::do t {User Manager {Billing Manager} Auditor} {
	$t add $usr $mgr $bil $aud
    }] show display
    return
}

proc ::stackato::cmd::usermgr::space-list {config} {
    debug.cmd/usermgr {}

    set thespace [cspace get]

    set dev [join [lsort -dict [$thespace @developers the_name]] \n]
    set mgr [join [lsort -dict [$thespace @managers   the_name]] \n]
    set aud [join [lsort -dict [$thespace @auditors   the_name]] \n]

    if {[$config @json]} {
	display [jmap map {dict {* array}} \
		     [dict create \
			  developer $dev \
			  manager   $mgr \
			  auditor   $aud]]
	return
    }

    display "Space [$thespace full-name] ..."
    [table::do t {Developer Manager Auditor} {
	$t add $dev $mgr $aud
    }] show display
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::usermgr::list {config} {
    debug.cmd/usermgr {}

    set client [$config @client]
    # logged in

    if {[$client isv2]} {
	ListV2 $config $client
    } else {
	ListV1 $config $client
    }
    return
}

proc ::stackato::cmd::usermgr::ListV1 {config client} {
    debug.cmd/usermgr {}

    set users [misc sort-aod email [$client users] -dict]
    
    if {[$config @json]} {
	display [jmap users $users]
	return
    }

    display ""
    if {![llength $users]} {
	display [color note "No Users"]
	return
    }

    set cu [$client current_user];#v1 - email

    [table::do t {{} Email Admin Applications} {
	foreach u $users {
	    set apps [struct::list map [dict getit $u apps] [lambda x {
		dict getit $x name
	    }]]
	    set apps [lsort -dict $apps]
	    set apps [join $apps {, }]
	    set apps [textutil::adjust::adjust $apps -length 60 -strictlength 1]

	    set name  [dict getit $u email]
	    set admin [dict getit $u admin]

	    $t add \
		[expr {($cu ne {}) && ($cu eq $name) ? "x" : ""}] \
		$name \
		$admin \
		$apps
	}
    }] show display
    return
}

proc ::stackato::cmd::usermgr::ListV2 {config client} {
    debug.cmd/usermgr {}

    if {![$config @json]} {
	display "Users: [context format-target]"
    }

    set mode [$config @mode]
    # derived conditions for groups of headings.
    set osa [expr {$mode in {all related}}]
    set ngf [expr {$mode in {all name}}]

    debug.cmd/usermgr {mode = $mode}
    debug.cmd/usermgr {osa  = $osa}
    debug.cmd/usermgr {ngf  = $ngf}

    # depth controlled by mode.
    if {$osa} {
	# inline all relations
	if {[$client is-stackato]} {
	    # stackato target, client uses the new efficient list
	    # format, we can go deep.
	    set depth 3
	} else {
	    # CF target, client sticks to the old list format, balance
	    # recursion to individual requests, go not as deep.
	    set depth 1
	}
    } else {
	# no relation asked for, drop from request
	set depth 0
    }

    # depth 2 for spaces of the users, and apps in spaces.
    # note: depth 0 for json, maybe.
    debug.cmd/usermgr {query cc /$depth}
    set users [v2 user list $depth include-relations spaces,managed_spaces,audited_spaces,organizations,billing_managed_organizations,managed_organizations,audited_organizations,apps]

    # Use the UAA list API to get its knowledge of users. This
    # prevents us from running lots of per-user queries of the same
    # information by v2user.

    # We can also use this to show users known only to the UAA but not
    # the CC, i.e. system inconsistencies. This part is disabled.

    debug.cmd/usermgr {query uaa}
    set uaaus [[client authenticated] uaa_list_users]

    debug.cmd/usermgr {U/cc_=[llength $users]}
    debug.cmd/usermgr {U/uaa=[llength $uaaus]}

    # index by guid
    foreach uaau $uaaus {
	set guid [dict get $uaau id]
	debug.cmd/usermgr {uaa has $guid}
	dict set umap $guid $uaau
    }

    # join with CC user data
    set mapped 0
    foreach u $users {
	set guid [$u @guid]
	if {![dict exists $umap $guid]} {
	    debug.cmd/usermgr {  uaa $guid unknown, ignored}
	    continue
	}
	$u uaa= [dict get $umap $guid]

	debug.cmd/usermgr {  uaa $guid joining cc = [$u @name] / [$u email]}
	dict unset umap $guid
	incr mapped
    }

    debug.cmd/usermgr {U/map=$mapped}

    # Disable display of unmapped UAA users by default.
    if {![$config @crosscheck]} {
	debug.cmd/usermgr {ignored aok/cc mismatches: [dict size $umap]}
	set umap {}
	# The map now contains only entries for users known to UAA but
	# not the main system.
    }

    debug.cmd/usermgr {sort by email}
    debug.cmd/usermgr {U/cc_=[llength $users]}

    set users [v2 sort the_name $users -dict]

    debug.cmd/usermgr {U/cc_=[llength $users]}

    if {[$config @json]} {
	set tmp {}
	foreach u $users {
	    lappend tmp [$u as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    if {![llength $users] && ![dict size $map]} {
	display [color note "No Users"]
	return
    }

    # TODO: users incomplete. Currently no perms.

    set cu [$client current_user_mail]

    debug.cmd/usermgr {begin table @@@@@@@@@@@@@@@@@@@@@@@@@@@}

    # full related Given Family Email Org/Space/App
    # ---- ------- ----- ------ ----- -------------
    #    0       0   x     x      x     
    #    0       1                x     x
    #    1       0   x     x      x     x
    #    1       1   x     x      x     x
    # ---- ------- ----- ------ ----- -------------
    set headings {{} Name {Last Login}}
    if {$ngf} { lappend headings Given Family }
    lappend headings Email
    if {$osa} { lappend headings Organizations Spaces Applications }

    set footnotes {}
    table::do t $headings {
	foreach u $users {
	    debug.cmd/usermgr {  process [$u url] = [$u @name] / [$u email] }

	    set email [$u email]
	    if {[string match {(legacy-api)} $email]} continue

	    if {[$u uaaerror] ne {}} {
		set email "Error ([llength $footnotes])"
		lappend footnotes "(Ad [llength $footnotes]): [$u uaaerror]"
	    }

	    set row {}

	    set admin [expr {[$u @admin] ? "A" : " "}]
	    set mark  [expr {($cu ne {}) && ($cu eq $email) ? "x" : " "}]

	    if {[catch {
		set ll [$u meta logged_in_at]
		set ll [pretty-since [since [epoch-of $ll]]]
	    }]} { set ll {not available} }

	    # Standard fields.
	    lappend row $mark$admin [$u the_name] $ll

	    if {$ngf} {
		lappend row [$u given_name] [$u family_name]
	    }

	    lappend row $email

	    if {$osa} {
		set smap [UserLinkedSpaces $u]
		set orgs [lsort -dict [dict keys [UserLinkedOrgs $u]]]

		# IV. Merge with applications by space and add to the table.
		debug.cmd/usermgr {  process [$u url] apps by space }
		set spaces {}
		set apps {}
		dict for {sname space} [dict sort $smap] {
		    set sapps [lsort -dict [$space @apps @name]]
		    foreach s [::list $sname] a $sapps {
			lappend spaces $s
			lappend apps   $a
		    }
		}

		lappend row [join $orgs \n] [join $spaces \n] [join $apps \n]
	    }

	    # All collected and formatted, add row for this user.
	    $t add {*}$row
	}

	if {[dict size $umap]} {
	    #$t add {} {} {} {}
	    $t add //////////////////////////////////// ///// ///// ////////////
	    dict for {g u} [dict sort $umap] {
		set n [dict get $u userName]
		$t add {} "$g ($n)" {} {} {} {} {} {}
	    }
	}
    }

    debug.cmd/usermgr {done_ table @@@@@@@@@@@@@@@@@@@@@@@@@@@}
    $t show display

    if {![llength $footnotes]} return
    display [join $footnotes \n]
    return
}

proc ::stackato::cmd::usermgr::UserLinkedSpaces {u} {
    debug.cmd/usermgr {  process [$u url] spaces }

    # Get all types of spaces (dev, managed, audited).
    # Merge them into a single colum with a role information prefix.

    # I. collect spaces and roles
    set smap  {} ;# full-name => entity
    set srole {} ;# full-name => roles

    foreach space [$u @audited_spaces] {
	set fn [$space full-name]
	dict set    smap  $fn $space
	dict append srole $fn A
    }
    foreach space [$u @managed_spaces] {
	set fn [$space full-name]
	dict set    smap  $fn $space
	dict append srole $fn M
    }
    foreach space [$u @spaces] {
	set fn [$space full-name]
	dict set    smap  $fn $space
	dict append srole $fn D
    }

    # II. Standardize the role information (fill missing parts)
    dict for {n r} $srole {
	dict set srole $n [dict get {
	    A   A--
	    AD  A-D
	    AM  AM-
	    AMD AMD
	    D   --D
	    M   -M-
	    MD  -MD
	} [dict get $srole $n]]
    }

    # III. Merge role information into the space map.
    set tmp {}
    dict for {n obj} $smap {
	dict set tmp "[dict get $srole $n] $n" $obj
    }

    # Return the final map (perm + name --> obj)
    return $tmp
}

proc ::stackato::cmd::usermgr::UserLinkedOrgs {u} {
    debug.cmd/usermgr {  process [$u url] orgs }

    # Get all types of orgs (dev, managed, billing, audited).
    # Merge them into a single colum with a role information prefix.

    # I. collect orgs and roles
    set omap  {} ;# full-name => entity
    set orole {} ;# full-name => roles

    foreach org [$u @audited_organizations] {
	set fn [$org @name]
	dict set    omap  $fn $org
	dict append orole $fn A
    }
    foreach org [$u @managed_organizations] {
	set fn [$org @name]
	dict set    omap  $fn $org
	dict append orole $fn M
    }
    foreach org [$u @organizations] {
	set fn [$org @name]
	dict set    omap  $fn $org
	dict append orole $fn D
    }
    foreach org [$u @billing_managed_organizations] {
	set fn [$org @name]
	dict set    omap  $fn $org
	dict append orole $fn B
    }

    # II. Standardize the role information (fill missing parts)
    dict for {n r} $orole {
	dict set orole $n [dict get {
	    A    A---
	    AB   AB--
	    AD   A--D
	    ADB  AB-D
	    AM   A-M-
	    AMB  ABM-
	    AMD  A-MD
	    AMDB ABMD
	    B    -B--
	    D    ---D
	    DB   -B-D
	    M    --M-
	    MB   -BM-
	    MD   --MD
	    MDB  -BMD
	} [dict get $orole $n]]
    }

    # III. Merge role information into the org map.
    set tmp {}
    dict for {n obj} $omap {
	dict set tmp "[dict get $orole $n] $n" $obj
    }

    # Return the final map (perm + name --> obj)
    return $tmp
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::usermgr::token {config} {
    debug.cmd/usermgr {}

    set target [$config @target]

    say "Get your login token at $target/login?print_token=1"

    set token [ask string* "Enter your token: "]

    if {$token eq {}} {
	err "Need a proper token."
    }

    Debug.cmd/usermgr {token = ($token)}

    set retriever [client restlog [stackato::client new $target $token]]
    set key       [dict get' [$retriever get_ssh_key] sshkey {}]

    Debug.cmd/usermgr {key   = ($key)}

    # We remove a pre-existing token, this also removes the associated
    # ssh key file. This ensures that a token change on this login
    # (expired token) does not cause us to leave the ssh key file for
    # the old token behind, never to be removed (except through
    # running 'logout --all').
    targets remove $target
    targets add    $target $token $key

    # NOTE: Any adjunct information (org, space) we may still have for
    # the target is not touched (not removed, not changed).

    say [color good "Successfully logged into \[$target\]"]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::usermgr::login-fields {config} {
    debug.cmd/usermgr {}

    set client [$config @client]
    set fields [dict sort [$client login-fields]]

    if {[$config @json]} {
	display [jmap map {dict {* array}} $fields]
	return
    }

    [table::do t {Field Type Label} {
	foreach {name def} $fields {
	    lassign $def type label
	    $t add $name $type $label
	}
    }] show display
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::usermgr::login {config} {
    debug.cmd/usermgr {}

    set promptok [cmdr interactive?]
    set target   [$config @target]

    set tries 0
    while {1} {
	try {
	    # Implied interaction.
	    # Note: Was done before this procedure was invoked.

	    set client [$config @client]
	    if {[$client isv2]} {
		set api V2
		lassign [LoginV2 $client $config] token sshkey
	    } else {
		set api V1
		lassign [LoginV1 $client $config] token sshkey
	    }

	    # We remove a pre-existing token, this also removes the
	    # associated ssh key file. This ensures that a token change on
	    # this login (expired token) does not cause us to leave the
	    # ssh key file for the old token behind, never to be removed
	    # (except through running 'logout --all').

	    targets  remove $target
	    targets  add    $target $token $sshkey

	    # Note: The addition of adjunct information is handled by
	    # the PostLogin* procedures, if any.

	    say [color good "Successfully logged into \[$target\]"]

	    set client [Regenerate $config]

	    # The API version was determined before the regeneration,
	    # avoiding a redundant /info call.
	    PostLogin$api $client $config
	    return

	} trap {STACKATO CLIENT TARGETERROR} e {
	    display [color bad "Problem with login, invalid account or password while attempting to login to '$target'. $e"]

	    incr tries
	    if {($tries < 3) && $promptok && ![HasPassword $config]} continue
	    exit fail
	    break

	} trap {REST HTTP}                  {e o} - \
	  trap {REST SSL}                   {e o} - \
	  trap SIGTERM                      {e o} - \
	  trap {TERM INTERUPT}              {e o} - \
	  trap {STACKATO SERVER DATA ERROR} {e o} - \
	  trap {STACKATO CLIENT}            {e o} - \
	  trap {CMDR PARAMETER UNDEFINED}   {e o} - \
	  trap {CMDR VALIDATE}              {e o} {
	    return {*}$o $e

	} on error e {
	    # Rethrow as internal error, with a full stack trace.
	    return -code error -errorcode {STACKATO CLIENT INTERNAL} \
		[::list $e $::errorInfo $::errorCode]
	}
    }
    return
}

proc ::stackato::cmd::usermgr::LoginV1 {client config} {
    debug.cmd/usermgr {}

    if {[cmdr interactive?]} {
	set target [$config @target]
	if {$target ne {}} {
	    display "Attempting login to \[$target\]"
	}
    }

    set name     [GetName             $config]
    set password [GetPassword $client $config]

    return [$client login $name $password]
}

proc ::stackato::cmd::usermgr::LoginV2 {client config} {
    debug.cmd/usermgr {}

    set target [$config @target]

    # Translate @email, @password into entries in the @credentials, if
    # they were specified on the command line.

    if {[$config @email set?]} {
	$config @credentials set "username: [$config @email]"
    }
    if {[$config @password set?]} {
	$config @credentials set "password: [$config @password]"
    }

    # Query target for the supported credential fields. We always need
    # this, for the interactive query, and to match them against the
    # non-interactively provided fields.

    set supported [$client login-fields]

    # Get the non-interactively provided fields, if any.

    set creds {}
    foreach kv [$config @credentials] {
	dict set creds {*}$kv
    }

    # Match supported and provided fields against each other.
    # (1) Provided, but unsupported fields are an error, always.
    # (2) Missing, but supported fields are an error if we cannot ask
    #     the user for their value. If we can, we do.

    dict for {field value} $creds {
	if {[dict exists $supported $field]} continue
	err "Credentials \"$field\" provided, but not supported by target \[$target\]"
    }

    if {[cmdr interactive?] && ($target ne {})} {
	display "Attempting login to \[$target\]"
    }

    dict for {field def} $supported {
	if {[dict exists $creds $field]} continue
	if {![cmdr interactive?]} {
	    err "Credentials \"$field\" not specified, but needed by target \[$target\]"
	}

	lassign $def ftype label
	debug.cmd/usermgr {${ftype}-field $field \$label\"}
	dict set creds $field [Get-$ftype $label]
    }

    # The credentials are now fine. Nothing unsupported in them, and
    # nothing missing either. We can now run the login.

    set token [$client login-by-fields $creds]

    # Pull the ssh key directly. This may fail. For the tech preview
    # we simply capture and display that error.

    set sshkey [client get-ssh-key $client]

    # Retrieve and save refresh token.
    tadjunct add $target refresh [$client refreshtoken]

    return [::list $token $sshkey]
}

proc ::stackato::cmd::usermgr::Get-text {label} {
    return [ask string "$label: "] 
}

proc ::stackato::cmd::usermgr::Get-password {label} {
    return [ask string* "$label: "] 
}

proc ::stackato::cmd::usermgr::GetName {config} {
    # CFv1 only
    debug.cmd/usermgr {}

    if {![$config @email set?] && [cmdr interactive?]} {
	$config @email set [ask string "Email: "] 
    }

    set email [$config @email]

    if {$email eq {}} {
	err "Need a valid email"
    }

    return $email
}

proc ::stackato::cmd::usermgr::GetPassword {client config} {
    # CFv1 only
    debug.cmd/usermgr {}

    set isadmin [$client admin?]

    debug.cmd/usermgr {Admin = $isadmin}
    # [bug 93843]
    if {$isadmin} {
	# This can be reached only for a v1 target.
	# assert: ![$client isv2]

	# NOTE V2: The UAA always requires a password. Admins
	#          cannot 'sudo' to other accounts without
	#          password anymore. The v2client instance behind
	#          $client knowns this and forces the !admin branch.

	# Note: With the restructuring for use of dynamically provided
	# fields for CFv2, i.e Stackato 3 the above is moot, as the
	# procedure is not used for the CFv2 branch at all anymore.

	set user [$client user]
	if {[HasPassword $config]} {
	    display "Ignoring password, logged in as administrator $user"
	} else {
	    display "No password asked for, logged in as administrator $user"
	}

	return {}
    }

    # Not an administrator.  Password is required.  Get a value, from
    # command line or through interaction.

    if {![$config @password set?] && [cmdr interactive?]} {
	$config @password set [string trim [ask string* "Password: "]]
    }

    set password [string trim [$config @password]]

    if {$password eq {}} {
	err "Need a password"
    }

    return $password
}

proc ::stackato::cmd::usermgr::PostLoginV1 {client config} {
    debug.cmd/usermgr {PostLogin CF v1}

    if {[$config @group set?]} {
	# --group provided, make persistent (implied 's group').
	# Run the misc command, to have all the necessary checks.

	cgroupcmd set-core $client [$config @group]
    } else {
	# On sucessful (re)login we reset the current group,
	# it may not be valid for this user. We mention this
	# however if and only if the target supported groups.

	cgroupcmd reset-core $client
    }
    return
}

proc ::stackato::cmd::usermgr::PostLoginV2 {client config} {
    debug.cmd/usermgr {begin/}

    # Handle chosen/current organization and space.

    # 1a. If an org is chosen validate its existence (search-by-name).
    # 1b. If none is chosen a cached current org is used, if ok, or
    #     re-chosen by the user.

    if {[$config @organization set?]} {
	set name [$config @organization]
	debug.cmd/usermgr {-- Org  user choice: $name}

	set org  [orgname validate [$config @organization self] $name]
	debug.cmd/usermgr {-- Org  validated}

	corg set $org
	corg save
    } else {
	debug.cmd/usermgr {-- Org  current|interact}
	corg get-auto [$config @organization self]
	# includes saving
    }

    # 2a. If a space is chosen validate its existence
    #     (search-by-name), within the current org.
    # 2b. If none is chosen a cached current space is used, if ok, or
    #     re-chosen by the user.

    if {[$config @space set?]} {
	set name  [$config @space]
	debug.cmd/usermgr {-- Space user choice: $name}

	set space [spacename validate [$config @space self] $name]
	debug.cmd/usermgr {-- Space validated}
	# Validation implicitly uses corg as context.

	cspace set $space
	cspace save
    } else {
	debug.cmd/usermgr {-- Space current|interact}
	cspace get-auto [$config @space self]
	# includes saving
    }

    display [context format-large]
    client license-status $client 0

    debug.cmd/usermgr {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::usermgr::logout {config} {
    debug.cmd/usermgr {}

    # Note: @target and @all are exclusive.
    # If one is set the other cannot be.

    # TODO: Activity blinking
    if {[$config @all]} {
	debug.cmd/usermgr {ALL}

	targets  remove-all
	tadjunct remove-all
	say [color good "Successfully logged out of all known targets"]
	return
    }

    debug.cmd/usermgr {ONE}

    set target [$config @target]

    debug.cmd/usermgr {target = $taget}

    targets  remove $target
    # Keep most adjunct information alive (org, space)
    # MUST destroy refresh, to prevent auto-relogin.
    tadjunct remove $target refresh

    say [color good "Successfully logged out of \[$target\]"]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::usermgr::password {config} {
    debug.cmd/usermgr {}

    # NOTE: passwd: Mixed use of --no-prompt. The command
    # NOTE: passwd: __always__ prompts for the old password
    # NOTE: passwd: to verify, even under --no-prompt.
    # NOTE: passwd: Option affects only input of new password,
    # NOTE: passwd: if not defined by option. But then that makes
    # NOTE: passwd: no sense, as it just forces an error.
    # NOTE: passwd:
    # NOTE: passwd: Might be best to remove all --no-prompt handling
    # NOTE: passwd: from the command. Of course, that makes it
    # NOTE: passwd: untestable by script also. So the alternative is
    # NOTE: passwd: to place the old password input under that flag also.
    # NOTE: passwd:
    # NOTE: passwd: The vmc client seems to have dropped the verification
    # NOTE: passwd: stage and simply requires user to be logged in.

    set promptok [cmdr interactive?]
    set client   [$config @client]

    set label  [expr {[$client isv2] ? "username" : "email"}]

    #debug.cmd/usermgr {password = "$password"}

    set email [$client current_user] ;#v1 - user email, v2 - user name
    if {$email eq {}} {
	set email [ask string "[string totitle $label]: "] 
	#err "Need to be logged in to change password."
    }

    say "Changing password for '$email'\n"

    if {![$client isv2]} {
	set target   [$config @target]
	set verifier [client restlog [stackato::client new $target {}]]

	set tries 0
	while {1} {
	    set oldpassword [string trim [ask string* "Old Password: "]]

	    # Verify that the old password is valid.
	    try {
		lassign [$verifier login $email $oldpassword] vtoken vsshkey

		targets add $target $vtoken $vsshkey
		set client [Regenerate $config]

	    } trap {STACKATO CLIENT TARGETERROR} e {
		display [color bad "Bad password"]
		incr tries
		if {$tries < 3} continue
		exit fail
		break
	    } trap {REST HTTP}                  {e o} - \
	      trap {REST SSL}                   {e o} - \
	      trap SIGTERM                      {e o} - \
	      trap {TERM INTERUPT}              {e o} - \
	      trap {STACKATO SERVER DATA ERROR} {e o} - \
	      trap {STACKATO CLIENT}            {e o} {
		return {*}$o $e

	    } on error e {
		# Rethrow as internal error, with a full stack trace.
		return -code error -errorcode {STACKATO CLIENT INTERNAL} \
		    [::list $e $::errorInfo $::errorCode]
	    }
	    break
	}

	$verifier destroy
    } else {
	# CF v2: Just ask for the old password. The verification
	# happens with the new change_password REST call of the v2
	# client. No separate verification by re-login.

	set oldpassword [string trim [ask string* "Old Password: "]]
    }

    set password [$config @password] ;# default: empty
    if {![$config @password set?] && $promptok} {
	set password  [string trim [ask string* "New Password: "]]
	set password2 [string trim [ask string* "Verify Password: "]]
	if {$password ne $password2} {
	    err "Passwords did not match, try again"
	}
    }
    if {$password eq {}} {
	err "Password required"
    }

    # TODO? V2 cf does some sort of password strength check. This
    # check seems to be entirely local, i.e. not requiring a server
    # round trip. Might be useful to see how it is done and implement
    # our own.

    $client change_password [string trim $password] $oldpassword
    say [color good "\nSuccessfully changed password"]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::usermgr::who {config} {
    debug.cmd/usermgr {}

    set client [$config @client]
    if {[$client isv2]} {
	Who2 $client $config
    } else {
	Who1 $client $config
    }
    return
}

proc ::stackato::cmd::usermgr::Who1 {client config} {
    debug.cmd/usermgr {}

    set username [$client current_user];# v1 = user email

    if {[$config @json]} {
	display [jmap map array [::list $username]]
	return
    }

    display "\n\[$username\]"
    return
}

proc ::stackato::cmd::usermgr::Who2 {client config} {
    debug.cmd/usermgr {}

    set client   [$config @client]
    set username [$client current_user]      ;# v2 name
    set email    [$client current_user_mail] ;# v2 email

    if {[$config @json]} {
	display [jmap map dict \
		     [dict create \
			  name  $username \
			  email $email]]
	return
    }

    display "\n\[$username, $email\]"
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::usermgr::info {config} {
    debug.cmd/usermgr {}

    set client [$config @client]
    if {[$client isv2]} {
	InfoV2 $config $client
    } else {
	InfoV1 $config $client
    }
}

proc ::stackato::cmd::usermgr::InfoV1 {config client} {
    debug.cmd/usermgr {}

    set info [$client info]

    if {![dict exists $info user]} {
	return -code error \
	    -errorcode {STACKATO CLIENT AUTHERROR} \
	    ""
    }
    set info [$client user_info [dict get $info user]]

    if {[$config @json]} {
	display [jmap map {dict {apps array}} $info]
	return
    }

    table::do t {Key Value} {
	set apps {}
	foreach ai [dict get $info apps] {
	    lappend apps [dict get $ai name]
	}

	$t add Email  [dict get $info email]
	$t add Admin  [dict get $info admin]
	$t add Groups [join [dict get $info groups] \n]
	$t add Apps   [join [lsort -dict $apps] \n]
    }
    display ""
    $t show display
    return
}

proc ::stackato::cmd::usermgr::InfoV2 {config client} {
    debug.cmd/usermgr {}

    set theuser [username validate [$config @name self] [$config @name]]

    if {[$config @json]} {
	display [$theuser as-json]
	return
    }

    table::do t {Key Value} {
	$t add Name                    [$theuser @name]
	$t add Email                   [$theuser email]
	$t add Admin                   [$theuser @admin]
	$t add Spaces                  [join [lsort -dict [$theuser @spaces         full-name]] \n]
	$t add {Managed Spaces}        [join [lsort -dict [$theuser @managed_spaces full-name]] \n]
	$t add {Audited Spaces}        [join [lsort -dict [$theuser @audited_spaces full-name]] \n]
	$t add Organizations           [join [lsort -dict [$theuser @organizations                 @name]] \n]
	$t add {Managed Organizations} [join [lsort -dict [$theuser @managed_organizations         @name]] \n]
	$t add {Billing Organizations} [join [lsort -dict [$theuser @billing_managed_organizations @name]] \n]
	$t add {Audited Organizations} [join [lsort -dict [$theuser @audited_organizations         @name]] \n]
    }
    display ""
    $t show display
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::usermgr::decode-token {config} {
    debug.cmd/usermgr {}
    # v2 only.

    set token [$config @token]
    debug.cmd/usermgr {token/0 = ($token)}

    # Trim non-coding prefix.
    regsub {^bearer } $token {} token
    debug.cmd/usermgr {token/1 = ($token)}

    set parts [split $token .]

    if {[llength $parts] == 1} {
	# v1 token. Decode, re-split on : and print.

	puts CFv1:
	set n 0
	foreach part [split [base64::decode [lindex $parts 0]] :] {
	    puts "\[$n\]: $part"
	    incr n
	}
    } else {
	# v2 token. Note: last part is the hash, in binary.
	set hash [lindex $parts end]

	puts CFv2:
	set n 0
	foreach part [lrange $parts 0 end-1] {
	    # base64url encoding -- http://tools.ietf.org/html/rfc4648#section-5
	    set part [string map {- + _ /} $part]

	    set pad [expr {[string length $token] % 4}]
	    if {$pad} {
		append part [string repeat = [expr {4-$pad}]]
	    }
	    puts "\[$n\]: [base64::decode $part]"
	    incr n
	}
	binary scan $hash H* hash
	puts "\[$n\]: $hash"
    }

    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::usermgr::Regenerate {config} {
    # Full reload of the (client) configuration.
    cgroup reset
    auth   reset
    client plain-reset 
    $config forget
    $config force

    return [$config @client]
}

proc  ::stackato::cmd::usermgr::HasPassword {config} {
    expr {[$config @password set?] &&
	  ([string trim [$config @password]] ne {})}
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::usermgr 0
return
