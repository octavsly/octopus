#
#    octopus: package of useful procedures
#    Copyright (C) 2012-2013 Octavian Petre <octavsly@gmail.com>
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

package provide octopus 0.1

package require Tcl 8.3
package require libterm 0.9.0


namespace eval ::octopus:: {
	namespace import ::libterm::*
	namespace export \
			set_octopus_color \
			display_message \
			extract_check_options_data \
			debug_variables \
			summary_of_messages \
			abort_on \
			check_file \
			calling_proc \
			true_if_number

	variable index 0
	variable authors "Octavian Petre"
	variable authors_email "octavsly@gmail.com"
	variable url_project {https://github.com/octavsly/octopus}

	variable prog_name ""
}


################################################################################
# BEGIN set_octopus_color
# enables/disables colors in outputs
proc ::octopus::set_octopus_color args {

	global ansi

	set var_array(disable)	[list "--disable" "false" "boolean" "" "" "" "Disables the colorful output. Useful for log files."]

	::octopus::extract_check_options_data

	::octopus::abort_on error --return --display-help

	if { "$disable" == "false" } {
		set ansi 1
	} else {
		set ansi 0
	}
}
# END color_setting
################################################################################


################################################################################
# BEGIN calling_proc
# Description:
#	Returns the calling procedure name. If there is an argument then it
#	will return the caller's caller name and so forth
#	http://tclhelp.net/unb/96
proc ::octopus::calling_proc { {offset 0} } {
	global argv0
	variable prog_name

	set lvl [expr [info level] - 2 - $offset]
	if { $lvl <= 0 } {
		if { $prog_name != "" } {
			return "$prog_name"
		} else {
			return "$argv0"
		}
	} elseif { $lvl > [info level] } {
		set lvl [info level]
	}
	return "[lindex [split [info level $lvl]] 0]"
}
# END calling_proc
################################################################################


################################################################################
# BEGIN display_message
# Procedure used in many flow_*.tcl scripts to generate unified error messages
proc ::octopus::display_message args {

	upvar execution_trace execution_trace

	set type_msg	[lindex $args 0]
	set string_msg 	[lindex $args 1]

	#extract from which level we display this message
	set dl 1
	regexp {<([0-9]+)>[\s]*(.*)} $string_msg match dl string_msg
	if { ([info exists execution_trace(debug-level) ] && $execution_trace(debug-level) > 99) } {
	     	set string_msg "[::octopus::calling_proc]: $string_msg"
	}
	switch -- $type_msg {
		error {
			::libterm::rtputs -nonewline "%d%l%#RERROR:%n  "
			::libterm::rtputs "	$string_msg"
			lappend execution_trace(errors_list) $string_msg
		}
		warning {
			::libterm::rtputs -nonewline "%d%#YWARNING:%n"
			::libterm::rtputs "	$string_msg"
			lappend execution_trace(warnings_list) $string_msg
		}
		info {
			::libterm::rtputs -nonewline "%#GINFO:%n   "
			::libterm::rtputs "	$string_msg"
			lappend execution_trace(infos_list) $string_msg
		}
		tip {
			::libterm::rtputs -nonewline "%#MTIP:%n	"
			::libterm::rtputs "	$string_msg"
			lappend execution_trace(tips_list) $string_msg
		}
		fixme {
			::libterm::rtputs -nonewline "%r%uFIXME!!%n"
			::libterm::rtputs "	 $string_msg"
			lappend execution_trace(fixmes_list) $string_msg
		}
		workaround {
			#::libterm::tputs -nonewline "%l%d%g%#MWORKAROUND:%n%n%n%n"
			::libterm::rtputs -nonewline "%rWORKAROUND:%n"
			::libterm::rtputs "     $string_msg"
			lappend execution_trace(workarounds_list) $string_msg
		}
		debug {
			if {([info exists execution_trace(debug-level)] && $execution_trace(debug-level) >= $dl) } {
				::libterm::rtputs -nonewline "%w%#KDEBUG:<$dl>%n"
				::libterm::rtputs "      $string_msg"
				lappend execution_trace(debugs_list) $string_msg
			}
		}
		none {
			::libterm::rtputs "            $string_msg"
		}
		dev_error {
			::libterm::rtputs -nonewline "%d%l%#RERROR:%n  "
			::libterm::rtputs "	<DEVELOPER ERROR:contact $::octopus::authors_email> $string_msg"
			lappend execution_trace(errors_list) $string_msg
		}
		contact {

				::libterm::rtputs -nonewline ""
				::libterm::rtputs -nonewline "Contact:"
				::libterm::rtputs "      Send suggestion to $::octopus::authors_email and/or"
				::libterm::rtputs "      $::octopus::url_project"
			}
		default {
			::libterm::rtputs "		  $string_msg"
		}
	}

}
# END display_message
################################################################################


################################################################################
proc ::octopus::abort_on args {

	set var_array(10,type)		[list "<orphaned>" "<none>" "string" "1" "infinity" "error warning info fixme tip workaround debug" "Type of messages the calling procedure will abort/return"]
	set var_array(20,return)	[list "--return" "false" "boolean" "" "" "" "Return instead of exit"]
	set var_array(30,suspend)	[list "--suspend" "false" "boolean" "" "" "" "Suspend. Useful, and available, only in RTL Compiler environment."]
	set var_array(40,display-help)	[list "--display-help" "false" "boolean" "" "" "" "Display help message of the calling procedure"]
	set var_array(50,messages)	[list "--messages" "false" "boolean" "" "" "" "Display the trigger message"]
	set var_array(60,no-cascading)	[list "--no-cascading" "false" "boolean" "" "" "" "Will not append the mesage list to higher level"]

	::octopus::extract_check_options_data

	if { "$suspend" == "true" && "[uplevel #0 {file tail $argv0} ]" != "rc" } {
		display_message error "Suspend not available in other environments than RTL Compiler"
		exit 1
	}

	foreach crt_type $type {
		if { [uplevel "info exists execution_trace(${crt_type}s_list)" ] } {
			if { "$messages" == "true" } {
				#::octopus::summary_of_messages --parent $crt_type
				uplevel "::octopus::summary_of_messages $crt_type"
			}
			if { "${display-help}" == "true" } {
				catch { uplevel ::octopus::display_help}
			}
			
			if { "$suspend" == "true" } {
				suspend
			} elseif { "${return}" == "true" } {
				if { "${no-cascading}" == "false" } {
					# This procedure messages exported one level higher
					octopus::append_cascading_variables
					# The calling procedure messages exported one level higher
					uplevel {octopus::append_cascading_variables}
				}
				# level not implemented in temposync(uses old TCL env)
				if { [catch { return -level 2 1 } ] } {	return -code 2 1 }
			} else {
				exit 1
			}
		}
	}
}
# END
################################################################################


################################################################################
# BEGIN displays a summary of messages
proc ::octopus::summary_of_messages args {

	upvar execution_trace execution_trace_parent

	set allowed_types "error warning info tip fixme workaround debug"

	set var_array(10,type)    [list "<orphaned>" "<none>" "string" "1" "infinity" "$allowed_types all" "Type of message for which the summary is displayed. all means all of them"]
	::octopus::extract_check_options_data

	if { "$type" == "all" } {set type "$allowed_types"}

	foreach crt_type $type {
		if { [info exists execution_trace_parent(${crt_type}s_list)] } {
			display_message info [string toupper "==Summary of ${crt_type}s=========="]
			foreach crt_msg $execution_trace_parent(${crt_type}s_list) {
				display_message $crt_type $crt_msg
			}
			puts ""
		} else {
			display_message info "Good... no [string toupper ${crt_type}]s found"
		}
	}
}
# END
################################################################################


################################################################################
# BEGIN true_if_number
# This procedure checks if the arguments is a number
# The procedure returns 1 if this is a number, otherwise it returns 0
proc ::octopus::true_if_number { tocheck } {

    if {![catch {expr $tocheck}]} {
        # your check says this is a number
        return 1
    } else {
        # your check says this is NOT a number
        return 0
    }
}
# END true_if_number
################################################################################


################################################################################
# BEGIN extract_check_options_data
# Description:
#	This is a generic procedure for parsing command line options of procedures
#	It requires that the var_array is set at the calling procedure.
#       e.g. set var_array(#,var) [list "--option-name" "default value" "type" "min" "max" "valid options" "help"]
#
#	#,:			will be an index and will be used by the procedure displaying the help to assemble the options in the right order.
#	var:			this var will be visible at the calling procedure.
#	--option-name:		the option passed to the procedure/script. Recommended to
#				have --option instead of -option, although supported.
#				<orphaned> can be used instead of an option to indicate that arguments should be accepted without having an option associated with them.
#	default value:		what is the default value if the option is not given at command line.
#				<none> is a special keyword specifying that this option MUST be specified since
#				there is no default value.
#	type:			the type of the argument. Allowed types: number, string, boolean, help, debug
#	min:			the minimum number of arguments allowed, following the option. Minimun value is 0
#	max:			the maximum number of arguments allowed, following the option. Maximum value is infinity.
#				infinity is a keyword specifying that any number of arguments can be specified
#	valid options: 		what values are allowed to be passed to the option. Empty string means that any value is valid
#	help:			The help message that will be printed when procedure/script is invoked with --help

# It should be noted that all procedures/scripts get several additional options:
#	--help:		will display the available help
#	--debug-level:	specify the debug level the procedure will run with, printing a lot more information
#	--no-colour:	to switch off the colour in displayed messages

# Examples of usage. See info_procedures.tcl

proc ::octopus::extract_check_options_data { } {

	upvar execution_trace execution_trace

	upvar argv passed_options_exec
	upvar args passed_options_proc
	upvar var_array var_array

	uplevel {global env}
	catch {set passed_options $passed_options_proc}
	catch {set passed_options $passed_options_exec}

	if { ! [info exists passed_options ] } {
		display_message error "Procedure [::octopus::calling_proc] is wrongly defined. Please replace list of variables with just args"
		return
	}

	if { [info exists var_array] && [llength "[array names var_array]"] == 0 } {
		display_message error "var_array, defined in [::octopus::calling_proc], needs to be an array"
		return
	}

	# Setting default value for debug level to the one of the calling procedure
	# In this way if no --debug-level option is specified use the parent level
	if { [info level] >= 2 && [uplevel 2 {info exists execution_trace(debug-level)} ] } {
		set dd [uplevel 2 {set execution_trace(debug-level)}]
	} else {
		set dd 0
	}
	# Add the help/debug automatically
	set var_array(z10,no-colour) 			[list "--no-colour" "false" "boolean" "" "" "" "Turns off colourful output (not recommended)." ]
	set var_array(z20,execution_trace(debug-level)) [list "--debug-level" "$dd" "debug" "" "" "" "Displays more debug information during the run. Default value is the calling debug level" ]
	set var_array(z30,help)				[list "--help" "false" "help" "" "" "" "This help message" ]

	#var_array contains indexes like "<10,variable>", to aid the correct display of the help. Get rid of these.
	foreach iii [array names var_array] {
		set var_array_trunk([variable_names $iii]) $var_array($iii)
	}

	# The values of the options need to be exported one level up
	foreach option_var [array names var_array_trunk] {
		if { "$option_var" != "execution_trace(debug-level)" } {
			upvar $option_var $option_var
		}
	}

	# Construct the list of possible arguments, do the first checks on what the user specified as parse-able options
	set allow_orphan_options false
	set accumulate_param_orphaned 0
	foreach option_var [array names var_array_trunk]  {
		set option_name 		[lindex $var_array_trunk($option_var) 0]
		set option_var_type	 	[lindex $var_array_trunk($option_var) 2]
		#				[lindex $var_array_trunk($option_var) 3] : minimum number of elements
		#				[lindex $var_array_trunk($option_var) 4] : maximum number of elements
		#				[lindex $var_array_trunk($option_var) 5] : allowed values
		if { [lsearch -exact "help debug number string boolean" $option_var_type] == -1 } {
			display_message error "$option_name option type set illegally to $option_var_type. Allowed types for options are: help, debug, number, string or boolean."

		}
		# BEGIN Overwrite some "lazy fields": fields which are not properly filled in
		if { "$option_var_type" == "boolean" || "$option_var_type" == "help" } {
			# boolean should have 0 param regardless what the calling procedure says.
			set var_array_trunk($option_var) [lreplace $var_array_trunk($option_var) 3 3 0]
			set var_array_trunk($option_var) [lreplace $var_array_trunk($option_var) 4 4 0]
		}
		if { "$option_var_type" == "debug" } {
			# debug is always a number regardless what the calling procedure says.
			set var_array_trunk($option_var) [lreplace $var_array_trunk($option_var) 3 3 1]
			set var_array_trunk($option_var) [lreplace $var_array_trunk($option_var) 4 4 1]
			set var_array_trunk($option_var) [lreplace $var_array_trunk($option_var) 2 2 "number"]
		}

		if { "[lindex $var_array_trunk($option_var) 3]" == "" } { set var_array_trunk($option_var) [lreplace $var_array_trunk($option_var) 3 3 0]}
		if { "[lindex $var_array_trunk($option_var) 4]" == "" } { set var_array_trunk($option_var) [lreplace $var_array_trunk($option_var) 4 4 0]}
		# END

		# BEGIN checks on user specified fields
		if { ! [true_if_number [lindex $var_array_trunk($option_var) 3]] } {
			display_message error "[::octopus::calling_proc]: the minimum number of elements must be a number or empty. Currently this is [lindex $var_array_trunk($option_var) 3]"
			return
		}
		if { ! [true_if_number [lindex $var_array_trunk($option_var) 4]] && "[lindex $var_array_trunk($option_var) 4]" != "infinity" } {
			display_message error "[::octopus::calling_proc]: the maximum number of elements must be a number, infinity keyword or just empty. Currently this is [lindex $var_array_trunk($option_var) 4]"
			return
		}
		# END

		if { [lindex $var_array_trunk($option_var) 3] > [lindex $var_array_trunk($option_var) 4] } {
			display_message error "[::octopus::calling_proc]: Minimum number of elements ($option_var_min_nr_elm) should not be bigger than the maximum number of elements ($option_var_max_nr_elm)."
			exit 1
		}

		if { "$option_name" != "<orphaned>" } {
			lappend allowed_options $option_name
		} else {
			set allow_orphan_options true
		}

		# Assign default values
		set default_value [lindex $var_array_trunk($option_var) 1]
		if { "$default_value" != "<none>" } {
			set $option_var $default_value
		}
		# Finally create a reversed index based on option names (those with -- in front)
		set opt_array($option_name) $option_var
	}

	################################################################################
	# BEGIN extracting the value
	set option_name ""

	foreach cur_option $passed_options {
		# For each option passsed to the procedure identify the parameters that should be respected
		if { [regexp -- {-+[^\s]*} $cur_option ] || "$cur_option" == ">" } {
			# This appears to be an option so search for it
			set found_option [lsearch -exact "$allowed_options" ${cur_option}]
			if { $found_option < 0 } {
				# User specified a fraction of the command
				set found_option [lsearch -all "$allowed_options" ${cur_option}*]
				if { [llength $found_option] > 1 } {
					display_message error "Option '${cur_option}', when calling '[::octopus::calling_proc]', can match several options: "
					foreach iii $found_option {
						display_message none "  [lindex $allowed_options $iii]"
					}
					continue
				} elseif { [llength $found_option] == 0 } {
					# There was no match, so most likely a wrong option specified
					set found_option -1
				}
			}
		} else {
			set found_option -1
		}

		if { $found_option >= 0 } {
			set option_name 		[lindex $allowed_options $found_option]
			set option_var			$opt_array($option_name)
			set option_var_type	 	[lindex $var_array_trunk($option_var) 2]
			set option_var_min_nr_elm 	[lindex $var_array_trunk($option_var) 3]
			set option_var_max_nr_elm 	[lindex $var_array_trunk($option_var) 4]
			set option_allowed_values 	[lindex $var_array_trunk($option_var) 5]

			if { "$option_var_type" == "help" } {
				catch { uplevel ::octopus::display_help }
				if { [catch { return -level 2 } ] } { return -code 2}
			}

			display_message debug "<99> Processing option type: '$option_var_type' "

			# Do some direct processing for boolean types of options
			if { "$option_var_type" == "boolean" || "$option_var_type" == "help" } {
				set $option_var "true"
				# reset the option_name so we can process others
				set option_name ""
			}

			# We have found an option, continue to process the args for that option
			set accumulate_param 0
			set nr_given_args($option_name) $accumulate_param
			continue
		}

		if { "$option_name" != "" && "$option_name" != "<orphaned>" } {
			# assign the values for the command line option
			# This is actualy the value we are searching for
			if { $accumulate_param == 0 } {
				# overwrite default value
				set $option_var $cur_option
			} else {
				lappend $option_var $cur_option
			}
			incr accumulate_param
			set nr_given_args($option_name) $accumulate_param
			# How many such parameters did we accumulate
			if { ("$option_var_max_nr_elm" != "infinite") && ($accumulate_param == $option_var_max_nr_elm) } {
				# we have reached the end of the parameters parsing for this active option.
				# Thus reset the option_name
				set option_name ""
				set accumulate_param 0
			}
		} else {
			if { "$allow_orphan_options" == "true" } {
				set option_name 		"<orphaned>"
				set option_var			$opt_array($option_name)
				set option_var_type	 	[lindex $var_array_trunk($option_var) 2]
				set option_var_min_nr_elm 	[lindex $var_array_trunk($option_var) 3]
				set option_var_max_nr_elm 	[lindex $var_array_trunk($option_var) 4]
				set option_allowed_values 	[lindex $var_array_trunk($option_var) 5]
				if { ("$option_var_max_nr_elm" != "infinite") && ($accumulate_param_orphaned < $option_var_max_nr_elm) } {
					if { $accumulate_param_orphaned == 0 } {
						set $option_var $cur_option
					} else {
						lappend $option_var $cur_option
					}
					incr accumulate_param_orphaned
					set nr_given_args($option_name) $accumulate_param_orphaned
				} else {
					display_message error "Unknown option $cur_option passed [::octopus::calling_proc]"
				}
			} else {
				display_message error "Unknown option $cur_option passed [::octopus::calling_proc]"
			}
		}
	}
	# END extracting the value
	################################################################################


	################################################################################
	# BEGIN checking the value
	# Check that all compulsory options, the ones which do not have default value, are specified
	# Assign default values, which can be overwritten later
	foreach option_var [array names var_array_trunk] {
		if { ![info exists $option_var] } {
			# This variable was never created while it should have been
			display_message error "Option [lindex $var_array_trunk($option_var) 0] is compulsory when calling '[::octopus::calling_proc]' procedure"
		}
	}
	# DO not use abort_on or you get an infinite loop
	if { [info exists execution_trace(errors_list) ] } { return }

	foreach option_var [array names var_array_trunk] {
		set option_name			[lindex $var_array_trunk($option_var) 0]
		set option_var_type		[lindex $var_array_trunk($option_var) 2]
		set option_var_min_nr_elm	[lindex $var_array_trunk($option_var) 3]
		set option_var_max_nr_elm	[lindex $var_array_trunk($option_var) 4]
		set option_allowed_values	[lindex $var_array_trunk($option_var) 5]
		if { "$option_var_type" == "number" && ! [ true_if_number [set $option_var] ] } {
			display_message error "When calling [::octopus::calling_proc], option passed to $option_name must be a number. Currently it is: [set $option_var]"
		}

		if { [info exists nr_given_args($option_name)] } {
			if { $nr_given_args($option_name) > $option_var_max_nr_elm || $nr_given_args($option_name) < $option_var_min_nr_elm } {
				display_message error "You have specified more/less number of arguments in [::octopus::calling_proc] for $option_name option."
			}
 		}

		if  { "$option_allowed_values" != "" } {
			foreach iii [set $option_var] {
				if { [lsearch -exact "$option_allowed_values" "$iii" ] == -1  } {
					display_message error "[::octopus::calling_proc] Only the following values are allowed for $option_name: $option_allowed_values. However there is: $iii"
				}
			}
		}
	}
	# END checking the value
	################################################################################
	if { "${no-colour}" == "true" } {
		::octopus::set_octopus_color --disable
	}
}
# END
################################################################################


################################################################################
# BEGIN
proc variable_names { vn } {
	foreach iii $vn {
		regexp {[0-9]*,(.*)} $vn match vn
		lappend accumulate $vn
	}
	return $accumulate
}
# END
################################################################################


###############################################################################
# BEGIN
proc ::octopus::display_help {} {

	upvar var_array var_array

	catch { uplevel eval $help_head }
	puts ""
	puts "Usage:"
	puts -nonewline "  [file tail [::octopus::calling_proc]] "
	set build_help ""
	set extended_help "Options:"
	set parse_twice 0
	set mol 0
	while { $parse_twice < 2 } {
		foreach iii [lsort [array name var_array]] {
			set option [lindex $var_array($iii) 0]
			regexp {[0-9]*,(.*)} $option match option
			set default [lindex $var_array($iii) 1]
			set type [lindex $var_array($iii) 2]
			set min_nr_arg [lindex $var_array($iii) 3]
			set max_nr_arg [lindex $var_array($iii) 4]
			set allowed_vallue [lindex $var_array($iii) 5]
			set help_text "[string trim [lindex $var_array($iii) 6] {.}]."
			if { "$option" == "<orphaned>" } {
				set option ""
			}
			if { "$type" == "number" || "$type" == "debug" } {
				set td "\<#\>"
			} elseif { "$type" == "string" } {
				set td "<string>"
			} elseif  { "$type" == "boolean" || "$type" == "help"} {
				set td ""
			}

			if { $max_nr_arg != "" && [true_if_number $max_nr_arg]  && $max_nr_arg > 1 } {
				set td "${td}...${td}"
			}
			if { "$default" != "<none>" && "$default" != "" } {
				set sbf "\["
				set sbr "\]"
				set def " Default value is %b${default}%n."
			} else {
				set sbf ""
				set sbr ""
				set def ""
			}
			if { "$allowed_vallue" != "" } {
				set td ""
				foreach jjj $allowed_vallue {
					set td "${td}|${jjj}"
				}
				set td [string range $td 1 end]
			} elseif { "$allowed_vallue" != "" } {
				set td "${td}\<$allowed_vallue\>"
			}
			if { [llength $td] >=1 } {set td " $td"}
			set build_help "$build_help ${sbf}${option}${td}${sbr}"
			if { $parse_twice == 0 } {
				set lot [string length "${option} ${td}"]
				if { $lot > $mol } {
					set mol $lot
				}
			} else {
				set ft [format "%-${mol}s" "${option} ${td}"]
				if { "${option}" == "--no-colour" } {
					set  extended_help "${extended_help}\n\nGeneral Options:"
				}
				set extended_help "${extended_help}\n    $ft : ${help_text}${def}"
			}
		}
		if { $parse_twice == 0 } {
			::libterm::rtputs $build_help
		} else {
			puts ""
			::libterm::rtputs $extended_help
		}

	incr parse_twice
	}
	puts ""
	catch { uplevel eval $help_tail }
}
# END
################################################################################


################################################################################
# BEGIN check if the file is a correct TCL.
# Returns a list with the files that pass the check

proc ::octopus::check_file args {

	set var_array(10,file)    [list "--file" "<none>" "string" "1" "infinity" "" "Check if the files are correct"]
	set var_array(20,type)    [list "--type" "<none>" "string" "1" "infinity" "exe tcl" "Type of checking. exe=executable, tcl=TCL compliancy"]
	::octopus::extract_check_options_data

	::octopus::abort_on error --return

	switch -- $type {
		tcl {
			foreach crt_file $file {
				if { [ catch {source $crt_file} errors ] } {
					display_message error "when sourcing $crt_file file"
					display_message none   "       Is this a TCL compliant file?"
					display_message none   "$errors"
				}
			}
			::octopus::abort_on error --return
		}
		exe {
			foreach crt_file $file {
				if { ! [file exists $crt_file ] || ! [file executable $crt_file] } {
					display_message error "$crt_file not found/executable. Do you have the right cadenv?"
				}
			}
			::octopus::abort_on error --return
		}
	}

	::octopus::append_cascading_variables
	return 0
}
# END
################################################################################


################################################################################
# BEGIN returns a list with the lists containing RTL/type/library/options
# Returns a list with the files that pass the check

proc ::octopus::parse_file_set args {

	set var_array(10,file)  	[list "--file" "<none>" "string" "1" "infinity" "" "The sourec files that need to be parsed"]
	set var_array(20,type)    	[list "--type" "<none>" "string" "1" "1" "utel diehard" "Type of file."]
	::octopus::extract_check_options_data

	::octopus::abort_on error --return

	set file_set_total ""
	switch -- $type {
		utel {
			foreach crt_file ${file} {
				# This file should defines a file_set variable
				if { [catch {source $crt_file} error_msg ] } {
					::octopus::display_message error "Sourcing $crt_file. Error is: $error_msg"
				}
				set file_set_total [concat $file_set_total $file_set]
			}
			::octopus::abort_on error --return
		}
		diehard {
			::octopus::display_message error "Not implemented for time being"
			::octopus::abort_on error --return
		}
	}

	::octopus::append_cascading_variables

	return $file_set_total
}
# END
################################################################################


################################################################################
# BEGIN returns a list with the lists containing RTL/type/library/options
# Returns a list with the files that pass the check

proc ::octopus::debug_variables args {

	set var_array(10,no-globals)  	[list "--no-globals" "false" "boolean" "" "" "" "Display the global variables."]
	set var_array(20,no-locals)    	[list "--no-locals" "false" "boolean" "" "" "" "Display the local variables."]
	set var_array(30,text)		[list "<orphaned>" "" "string" "1" "1" "" "Text to print before displaying the variables, to allow better pinpointing the location."]
	::octopus::extract_check_options_data

	::octopus::abort_on error --return

	if { "$text" != "" } {display_message none "$text"}

	if { "${no-locals}" == "false" } {
		display_message info "Local variable seen at [::octopus::calling_proc]"
		uplevel {
			foreach iii [info locals] {
				display_message none "%b$iii%n=[set $iii]"
			}
			unset iii
		}
	}
	if { "${no-globals}" == "false" } {
		display_message info "Global variable"
		uplevel {
			foreach iii [info globals] {
				catch {display_message none "%b$iii%n=[set $iii]"}
			}
			unset iii
		}
	}
}
# END
################################################################################


################################################################################
# BEGIN append_cascading_variables
# This procedures pushes up one level the execution_trace array

proc ::octopus::append_cascading_variables {} {

	uplevel {
		if { [info exists execution_trace] } {
			foreach index [array names execution_trace] {
				if { "$index" != "debug-level" } {
					uplevel "lappend execution_trace($index) $execution_trace($index)"
				}
			}
		}
	}
}
# END
################################################################################
