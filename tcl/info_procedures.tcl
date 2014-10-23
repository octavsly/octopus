#!/bin/sh
# the next line restarts using -*-Tcl-*-sh \
exec /usr/bin/tclsh "$0" ${1+"$@"}

if { [info exists env(OCTOPUS_INSTALL_PATH) ] } {
        lappend auto_path $env(OCTOPUS_INSTALL_PATH)
} else {
        puts "ERROR: Please set environmental variable OCTOPUS_INSTALL_PATH to point to the location of octopus.tcl (& more) file"
        exit 1
}

lappend auto_path $env(OCTOPUS_INSTALL_PATH)
package require octopus 0.1
package require octopusNC 0.1
package require octopusRC 0.1
package require octopusDS 0.1

set var_array(10,package)		[list "--package" "octopus octopusNC octopusRC octopusDS" "string" "1" "infinity" "octopus octopusNC octopusRC octopusDS" "Package used for requesting information. More than one package can be specified."]
set var_array(20,procedure)		[list "--procedure" "" "string" "1" "1" "" "The procedure for which name/help will be returned."]
set var_array(30,print)			[list "--print" "name" "string" "1" "1" "name help" "What to show. Name is the procedure(s) name while help is their help."]

set help_head {
	puts "[file tail $argv0 ]"
	puts ""
	puts "Description:"
	puts " Provides information for the octopus packages and their procedures."
	puts ""
}

set help_tail {
	puts "More information:"
	puts "  If no arguments are provided, all procedures from all packages will be returned"
}
::octopus::extract_check_options_data

::octopus::abort_on error --display-help

foreach crt_package $package {
	::octopus::display_message info "Package $crt_package"
	if { "$procedure" == "" } {
		set all_crt_procs [info procs "::${crt_package}::*"]
	} else {
		set all_crt_procs "::${crt_package}::$procedure"
	}
	::octopus::display_message none "Procedure(s)"
	foreach crt_proc $all_crt_procs {
		if { "$print" == "name" } {
			::octopus::display_message none "$crt_proc"
		} else {
			puts ""
			puts "--------------------------------------------------------------------------------"
			::octopus::display_message info "$crt_proc"
			if { [ catch {$crt_proc --help} ] } {
				::octopus::display_message warning "No help available for: $crt_proc"
			}
			puts "--------------------------------------------------------------------------------"
			puts ""
		}
	}
}