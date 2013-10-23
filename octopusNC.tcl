#
#    octopusNC: NVverilog, NCvhdl, NCcoex, NCsim package of useful procedures
#    Copyright (C) 2012-2013 Octavian Petre <octavsly@gmail.com>.
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

package provide octopusNC 0.1

package require Tcl 8.3
package require libterm 0.9.0
package require octopus 0.1


namespace eval ::octopusNC {
	namespace import ::libterm::*
	namespace import ::octopus::*

	namespace export \
			read_hdl \
			display_strange_warnings_fatals

	variable authors "Octavian Petre"
	variable authors_email "octavsly@gmail.com"
	variable url_project {https://github.com/octavsly/octopus}
}


################################################################################
# BEGIN read_hdl
# This procedure will be able to read RC code that uses read_hdl command
# It modifies the file_set variables
proc ::octopusNC::read_hdl args {

	upvar file_set file_set

	# This will help building the file list
	set var_array(vhdl) 	[list "-vhdl" "false" "boolean" "" "" "" ]
	set var_array(lib) 	[list "-library" "<none>" "string" "1" "1" "" ]
	set var_array(files)	[list "<orphaned>" "<none>" "string" "1" "infinity" ""]

	::octopus::extract_check_options_data

	if { "$vhdl" == "true" } {set type vhdl}
	if { "$vhdl" == "false" } {set type verilog}

	foreach crt_file $files {
		lappend file_set [list $crt_file  $type $lib "" ]
	}
	::octopus::append_cascading_variables

}
# END read_hdl
################################################################################


################################################################################
# BEGIN display_strange_warnings_fatals
# procedure searches through log files for uncommon messages
# TO DO: make it a general procedure to be used by other parts of octopus. Combine it with the temposync procedure which does something similar
proc ::octopusNC::display_strange_warnings_fatals args {

	add_option --name "--file" --max infinity --help-text "List of files required to parse the error messages"
	add_option --name "--after-lines" --default 3 --type "number" --help-text "How many lines to display after the string was detected"

	::octopus::extract_check_options_data

	display_message info "################################################################################"
	display_message info "BEGIN Searching for Errors/Fatal/Warnings (uncommon)"
	display_message info "--------------------------------------------------------------------------------"

	set search_strings  [list {\*E} {\*F} {\*W} {: error:}]
	set exclude_strings [list {CDS.LIB file included multiple} {default binding occurred for component instance} {Unable to list the views of bmslib.README} {Unable to find an 'hdl.var' file to load in} {*W,DLWNEW: Intermediate file} ]

	# Due to NFS problems it is advisable to run a ls before
	set file_on_disk "false"
	while { "$file_on_disk" == "false" } {
	    if { [glob -nocomplain $file ] == "" } {
	        #pesky NFS hasn't seen the file yet
	        set file_on_disk "false"
	        display_message info "Waiting for $file to appear on disk"
	    } else {
	        # Finaly the file has appeared on disk
	        set file_on_disk "true"
	    }
	    after 1000
	}

	foreach crt_log [glob $file ] {
		set fileId_log [open $crt_log {RDONLY} ]
		set al 0
		foreach line [split [read $fileId_log] \n] {
			# Process line
			foreach crt_ss $search_strings {
				if { [ string match "*${crt_ss}*" $line] } {
					set al ${after-lines}
					foreach crt_es $exclude_strings {
						if { [ string match "*${crt_es}*" $line] } {
							set al 0
							break
						}
					}

				}

			}
			if {$al > 0} {
				display_message warning $line
				set al [expr $al - 1]
			}
		}
		close $fileId_log
	}
	display_message info "--------------------------------------------------------------------------------"
	display_message info "END"
	display_message info "################################################################################"
	display_message info ""
	::octopus::append_cascading_variables
}
# END
################################################################################
