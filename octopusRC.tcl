#
#    octopusRC: RTL Compiler package of useful procedures
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

package provide octopusRC 0.1

package require Tcl 8.3
package require libterm 0.9.0
package require octopus 0.1


namespace eval ::octopusRC {
	namespace import ::libterm::*
	namespace import ::octopus::*

	namespace export \
			set_design_maturity_level \
			\
			modules_under \
			advanced_recursive_grouping\
			fan_hierarchical \
			\
			report_attributes \
			set_attribute_recursive \
			\
			define_dft_test_clocks \
			define_dft_test_mode \
			define_dft_test_signals \
			\
			find_fall_edge_objects \
			design_crawler \
			\
			generate_list_of_clock_inverters_for_dft_shell \

	variable authors "Octavian Petre"
	variable authors_email "octavsly@gmail.com"
	variable url_project {https://github.com/octavsly/octopus}

	# This variable controls the speed the netlists are generated.
	# Allowed values: fast, normal, slow
	#	fast:	no reports are generated,
	#		no db is written
	#		no lec is written
	#	normal: to be defined
	#	slow: to be defined
	variable run_speed "fast"
	variable previous_stage ""
}


################################################################################
# BEGIN set_design_maturity_level
# This procedure sets the maturity level of the design and sets attributes from the specified --rc-attributes-file
proc ::octopusRC::set_design_maturity_level args {

	set  help_head {
		::octopus::display_message none "Set the RC attributes based on the design maturity level"
	}

	::octopus::add_option --name "--maturity-level" --default "final" --valid-values "pre-alpha alpha beta release-candidate final" --help-text "Specify the maturity level of the design."
	::octopus::add_option --name "--rc-attributes-file" --default "rc_attributes.txt" --max "infinity" --help-text "Specify the file from which settings will be extracted."

	extract_check_options_data ; #description of var_array variable is given in this procedures

	::octopus::abort_on error --return --display-help

	::octopus::display_message info		"Setting design maturity level to ${maturity-level}"
	::octopus::display_message warning	"maturity level setting is in ALPHA stage"

	# Nice feature of RC, allowing user defined attributes
	define_attribute \
		octopusRC_design_maturity_level \
		-category user \
		-obj_type root \
		-data_type string \
		-default_value ${maturity-level} \
		-help_string "Define the maturity level of the design. Can be pre-alpha, alpha, beta, release-candidate or final."

	# Parse setting.tcl file and set the attributes
	foreach caf ${rc-attributes-file} {
		set fileID [open ${caf} {RDONLY} ]
		foreach line [split [read $fileID] "\n"] {
			::octopus::display_message debug "<20> Processing line: $line"
			# Process line
			if { [ regexp {^[\s]*#} $line match] } {
				# comments so just continue
				continue
			}
			if { [ regexp {[\s]*([^\s]+)[\s]+([^\s]+)[\s]+([^\s]+)[\s]+([^\s]+)[\s]+([^\s]+)[\s]+([^\s]+)[\s]+(.*)} $line match \
				rc_attribute value(pre-alpha) value(alpha) value(beta) value(release-candidate) value(final) comment ] } {
				if { "$value(${maturity-level})" != "-" } {
					::octopus::display_message debug "<2> set_attribute $rc_attribute $value(${maturity-level})"
					set_attribute $rc_attribute $value(${maturity-level})
				} else {
					::octopus::display_message debug "<2> Using default attribute for $rc_attribute : [get_attribute $rc_attribute]"
				}
				if { ${rc_attribute} == "hdl_track_filename_row_col" } {
					::octopus::display_message warning "hdl_track_filename_row_col attribute is known to create problems like slow-down and crashes"
				}
			}
		}
		close $fileID
	}

	set synthesis_effort(pre-alpha)	medium
	set synthesis_effort(alpha)	high
	set synthesis_effort(beta)	high
	set synthesis_effort(release-candidate)	high
	set synthesis_effort(final)	high

	::octopus::append_cascading_variables
}
# END
################################################################################


################################################################################
# BEGIN modules_under
# This procedure will return a list will modules used by a certain module until
# a ceratin level
# Options:
#	--max_levels <number> 		max number of recursion levels.
#					Default is infinity
#	--module_name <name>		the name of the module
proc ::octopusRC::modules_under args {

	set  help_head {
		::octopus::display_message none "Returns a list will all modules instantiated under one or more modules"
	}

	::octopus::add_option --name "--max-levels" --default "infinity" --help-text "How many levels of recursion should go under the specified module"
	::octopus::add_option --name "--module-names" --help-text "Module name for which the modules will be listed"

	extract_check_options_data ; #description of var_array variable is given in this procedure

	::octopus::display_message error "Procedure ::octopusRC::modules_under not implemented"
	::octopus::append_cascading_variables

}
# END modules_under
################################################################################


################################################################################
# BEGIN rec_grouping
# this procedure parses recursively all instances under parrent_instance
# and groups everything except parrents of exclude-parents-of-instances
proc ::octopusRC::rec_grouping {parrent_instance list_instances_under_parent} {

	# Avoid memory consumption for fixed values of variable
	upvar exclude-parents-of-instances exclude-parents-of-instances
	upvar list_of_parsed_modules list_of_parsed_modules
	upvar level level
	upvar execution_trace execution_trace

	incr level
	::octopus::display_message debug "<1> Entering: $parrent_instance (Recursion level:$level)"

	set list_of_instances_to_group ""
	::octopus::display_message debug "<2> Going through: $list_instances_under_parent"
	foreach crt_inst $list_instances_under_parent {
		if { [string match "* ${crt_inst} *" " ${exclude-parents-of-instances} "] } {
		# We have found the exact match to an always ON instance
		::octopus::display_message debug "<1>     SKIPPING exact ${crt_inst}"
		} else {
			if { [string match "* ${crt_inst}*" " ${exclude-parents-of-instances} "] } {
				# An always ON instance is under this instance
				# This instance does not need to be grouped
				# continue underneath
				set crt_module ""
				if { [ catch { set crt_module [get_attribute subdesign ${crt_inst}] } ] == 0 } {
					if { [ lsearch -exact $list_of_parsed_modules $crt_module ] == -1 } {
						# This check agains the parsed modules is apparently not necesary. Spent 4 hours with this issue
						# but finaly I have found it. The explanation follows
						# If the netlist is not uniquified and a module which is instantiated several times gets modified
						# all instances will see the modifications.
						# Thus, if we detect an already parsed modules do not process it again.
						rec_grouping $crt_inst [find ${crt_inst} -instance -maxdepth  2 *]
						::octopus::display_message debug "<1>     SKIPPING       ${crt_inst}"
					}
				}
			} else {
				# Keep on constructing the list for grouping
				lappend list_of_instances_to_group $crt_inst
			}
		}
	}
	# We have circled through all instances in a certain level
	# Now group all collected instances if the level matches with what we have specified
	# thus preventing grouping everything together
	if {[llength $list_of_instances_to_group] !=0} {
		if { "${parrent_instance}" != "" } {
			::octopus::display_message debug "<1>     Grouping inside $parrent_instance"
			foreach aux $list_of_instances_to_group {
				::octopus::display_message debug "<1>     |-> $aux"
			}
			::octopus::display_message debug "<1>     --- "

			cd $parrent_instance
			edit_netlist group -group_name new_Inst_group_sw_domain_ $list_of_instances_to_group
		}
	}

	if { "${parrent_instance}" != "" && ! [ catch { set parrent_module [get_attribute subdesign $parrent_instance] } ] } {
		# Is not a library cell
		lappend list_of_parsed_modules $parrent_module
	}

	set level [expr $level - 1]
	::octopus::display_message debug "<1> Exiting $parrent_instance (Recursion level:$level)"
}
# END rec_grouping
################################################################################


################################################################################
# BEGIN advanced_recursive_grouping
# This procedure parse recursively the specified group_under_instances and groups all instances
# at each level that does not match the exclude_above_instances
# More information available <put wiki link with the documentation>
proc ::octopusRC::advanced_recursive_grouping args {

	set_attribute group_generate_portname_from_netname true /

	::octopus::add_option --name "--group-children-of-instances" --help-text "Group all children of the specified instance(s)"
	::octopus::add_option --name "--exclude-parents-of-instances" --help-text "During grouping, exclude all parent of the specified instance(s)"

	extract_check_options_data ; #description of var_array variable is given in this procedures

	::octopus::display_message fixme "Check that 'group-children-of-instances' and 'exclude-parents-of-instances' instances exist in the design"

	set list_of_parsed_modules ""
	set level 1
	foreach crt_inst ${group-children-of-instances} {
		rec_grouping $crt_inst [find ${crt_inst} -instance -maxdepth  2 *]
	}

	::octopus::display_message debug "<2> Exit"
	::octopus::append_cascading_variables
}
# END advanced_recursive_grouping
################################################################################


################################################################################
# BEGIN fan_hierarchical
# Returns a list with all pins at all hierarchical levels from the specified
# port(s) tracing fanin/fanout. It can be very useful for MSV designs where
# different isolation signals are requested.
# If this can be replaced by a simple RC command just modify it.
proc ::octopusRC::fan_hierarchical args {

	::octopus::add_option --name "--max-depth" --default "infinity" --type number --help-text "Maximum logic depth the trace should. Currently only 1 level is implemented."
	::octopus::add_option --name "--pin" --max "infinity" --help-text "Pin name with full cadence path, vname or not."
	::octopus::add_option --name "--fan" --valid-values "in out" --help-text "Type of fan."
	::octopus::add_option --name "--vname" --default "false" --type "boolean" --help-text "Return the string in vname format"
	::octopus::add_option --name "--include-nets" --default "false" --type "boolean" --help-text "Include nets during the traces. If this option is omitted, only ports are returned."

	extract_check_options_data ; #description of var_array variable is given in this procedures

	if { ${max-depth} > 1 } {
		::octopus::display_message error "--max-depth > 1 is not yet implemented"
	} else {
		set max-depth 1
	}

	::octopus::abort_on error --return --display-help

	set stop_at [fan${fan} -max_pin_depth ${max-depth} $pin]
	set max_rec_levels 9999
	set crt_rec_level 1
	set temp ""
	foreach crt_pin $pin {
		set temp [concat $temp [trace_pins_hierarchical $crt_pin]]
	}
	::octopus::append_cascading_variables
	return $temp
}

proc if_vname {pin} {
	upvar vname vname
	if { $vname == true } {
		lappend return_list [vname $pin]
	} else {
		lappend return_list $pin
	}
}

proc include_nets {net} {
	upvar include-nets include-nets
	upvar vname vname
	if { "${include-nets}" == "true" } {
		return [if_vname $net]
	} else {
		return
	}
}

proc trace_pins_hierarchical {pin} {

	upvar stop_at stop_at
	upvar fan fan
	upvar return_list return_list
	upvar max_rec_levels max_rec_levels
	upvar crt_rec_level crt_rec_level
	upvar vname vname
	upvar include-nets include-nets

	# Return the value of teh pin if we reached the end of recursion or we reached the maximum recursion levels
	if { [string match "* $pin *" " $stop_at "] || $crt_rec_level > $max_rec_levels || [string match "*/constants/*" $pin] > 0 } {
		return [ifvname $pin]
	}
	if { "$fan" == "in" } {
		set direction_check "in"
		set direction_check_n "out"
		set driver_loads "driver"
	} elseif { "$fan" == "out" } {
		set direction_check "out"
		set direction_check_n "in"
		set driver_loads "loads"
	} else {
		::octopus::display_message error "fan can be either in or out. It is currently $fan"
		return
	}
	# Variable to acuumulate the ports that will be returned.
	set accumulate_ports ""
	# get the net name the pin is connected to.
	set net [get_attribute net $pin]
	# get the driver of this net. Usualy another pin. Thus calling this the next pin to process
	set next_pin [get_attribute $driver_loads $net]
	# If the next_pin is a constant return
	if { [string match "*/constants/*" $next_pin] > 0 } { return }
	# We might have multiple drivers
	foreach crt_next_pin $next_pin {
		# Is the driver part of a hierarchical instance?
		set hierarchical_attribute [get_attribute hierarchical [dirname $crt_next_pin -times 2]]
		# What is the pin direction
		set pin_direction [get_attribute direction $crt_next_pin]
		# Prepare the pin since it's going to be used several times
		set pin_converted_crt_next_pin [find [dirname $crt_next_pin -times 2] -maxdepth 2 -pin [file tail $crt_next_pin]]
		if { "$pin_direction" == "inout" } {
			#not yet dealing with inouts
			::octopus::display_message error "Stopping tracing at inout pin $crt_next_pin. result might be inaccurate"
			set accumulate_ports [concat $accumulate_ports [if_vname $crt_next_pin]]
		} elseif { "$pin_direction" == "$direction_check" } {
			# Might be a subport so we need to use the pin
			set accumulate_ports [concat $accumulate_ports [if_vname $pin_converted_crt_next_pin] [trace_pins_hierarchical $pin_converted_crt_next_pin] ]
		} elseif { "$pin_direction" == "$direction_check_n" && "$hierarchical_attribute" == "true" } {
			# need to trace the subports instead of pin
			set crt_next_pin [find [dirname $crt_next_pin -times 2] -maxdepth 2 -subport [file tail $crt_next_pin]]
			set accumulate_ports [concat $accumulate_ports [if_vname $pin_converted_crt_next_pin] [trace_pins_hierarchical $crt_next_pin] ]
		} elseif { "$pin_direction" == "$direction_check_n" && "$hierarchical_attribute" != "true" } {
			# This is a library port. Add it to the list and continue
			set accumulate_ports [concat $accumulate_ports $crt_next_pin]
		} else {
			::octopus::display_message error "I am not supossed to be here."
			::octopus::display_message none "pin_direction=$pin_direction"
			::octopus::display_message none "hierarchical_attribute=$hierarchical_attribute"
		}
	}
	return [concat [include-nets $net] $accumulate_ports]
}
# END fanin_hierarchical
################################################################################


################################################################################
# BEGIN report_attributes
proc ::octopusRC::report_attributes args {

	::octopus::add_option --name "--objects"  --max "infinity" --help-text  "RC objects for which we want to return a list of attributes. Most likely objects found by \[find / -<type> <search>\]"
	::octopus::add_option --name "--attributes" --max "infinity" --help-text "Any valid object attribute, such as load/driver/etc."
	::octopus::add_option --name ">" --default "stdout" --help-text "Redirects the output to a file"

	extract_check_options_data ; #description of var_array variable is given in this procedures

	::octopus::abort_on error --return --display-help

	puts -nonewline $redirect_fileId "Instance"
	foreach crt_att $attributes {
		puts -nonewline $redirect_fileId " :${crt_att}: "
	}
	puts $redirect_fileId ""
	puts $redirect_fileId "================================================================================"

	# Sometimes the user uses a find command which returns the result with {}
	foreach iii [split "${objects}" " \{\}"] {
		if { "$iii" != "" } {
			puts -nonewline $redirect_fileId "[vname $iii]"
			foreach crt_attr $attributes {
				catch {puts -nonewline $redirect_fileId " :[file tail [get_attribute $crt_attr $iii]]: "}
			}
			puts $redirect_fileId ""
		}
	}
	puts $redirect_fileId "================================================================================"
	if { "$redirect" != "stdout" } { close $redirect_fileId }
	::octopus::append_cascading_variables
}
# END report attributes
################################################################################


################################################################################
# BEGIN set_attribute_recursive
proc ::octopusRC::set_attribute_recursive args {

	::octopus::add_option --name "--attribute" --min 2 --max 2 --help-text "Specify the attribute to be applied. Format is: attribute <true|false>."
	::octopus::add_option --name "--objects" --max "infinity" --help-text "Specify the objects for which the attributes will be applied. e.g. instances/modules/pins/etc."
	::octopus::add_option --name "--direction" --default "down" --valid-values "up down both" --help-text "Specify the direction of	recursion. up: all parents will get the attribute, down: all children.	both: all parents and children"

	set help_tail {
		puts "More information:"
		puts "    --objects:   While pins, or other projects, can be specified, it makes no sense, since recursion is not yet implemented"
	}

	extract_check_options_data ; #description of var_array variable is given in this procedures

	::octopus::abort_on error --return --display-help


	if { "$direction" != "up" } {
		::octopus::display_message error "Direction $direction not implemented"
	}

	# Flatten several; find lists. Is there a better way?
	set iii ""
	foreach crt_obj "${objects}" {
		set iii [concat $iii $crt_obj]
	}
	set objects $iii

	set safe 0
	if { "$direction" == "up" } {
		foreach crt_obj $objects {
			set vco [vname $crt_obj]
			while { "$vco" != "." && $safe < 9999 } {
				set_attribute [lindex $attribute 0 ] [lindex $attribute 1 ] $vco
				set vco [file dirname $vco]
				incr safe
				::octopus::display_message debug "<10> Remaining to process: $vco"
			}
		}
	}
	if { $safe >= 9999 } {
		::octopus::display_message error "Maximum number of instances achieved, being $safe. Not all instances received the attribute."
	}
	::octopus::append_cascading_variables
}

# END
################################################################################


################################################################################
# BEGIN define_dft_test_clocks
# take clocks already defined in SDC
proc ::octopusRC::define_dft_test_clocks args {

	# Find available timing modes
	set timing_modes ""
	foreach iii [find / -vname -mode *] {
		lappend timing_modes [file tail $iii]
	}

	::octopus::add_option --name "--timing-modes" --max "infinity" --valid-values "$timing_modes" --help-text "The timing mode(s) the clocks will be extracted from to be added as DfT clocks" 
	::octopus::add_option --name "--skip-clocks" --default "" --max "infinity" --help-text "Skip the specified clocks from the constraints to be added as DfT clocks"
	::octopus::add_option --name "--add-clocks" --default "" --max "infinity" --help-text "Add the specified clocks, and not part of SDC constraints, in the DfT clocks."

	extract_check_options_data ; #description of var_array variable is given in this procedures

	::octopus::abort_on error --return --display-help

	::octopus::display_message info "BEGIN Defining test clocks from SDC"

	set all_clocks ""
	# Check that all clocks specified by add-clocks is a valid object
	foreach crt_add_clock ${add-clocks} {
		if { "${add-clocks}" != "" && [catch {lappend all_clocks [ls $crt_add_clock]} ] } {
			::octopus::display_message error "$crt_add_clock does not exist in the design"
		}
	}
	foreach crt_skip_clock ${skip-clocks} {
		if { "${skip-clocks}" != "" && [catch {lappend all_clocks [ls $crt_skip_clock]} ] } {
			::octopus::display_message error "$crt_skip_clock does not exist in the design"
		}
	}

	::octopus::abort_on error --return

	foreach iii ${timing-modes} {
		set tiii [file tail $iii]
		::octopus::display_message debug "<5> Extracting clocks of timing mode $iii"
		set aux [find /*/*/modes/$tiii/clock_domains/*/ -clock *]
		::octopus::display_message debug "<15> Clocks found: $aux"
		set all_clocks "$all_clocks $aux"
	}

	set all_clock_drivers ""
	foreach crt_clock "$all_clocks" {
		set clock_name [file tail $crt_clock]
		if { [catch {set clock_driver [get_attribute non_inverted_sources $crt_clock]} ] } {
			::octopus::display_message error "Is $crt_clock a clock signal?"
			continue
		}
		set aux_clock_driver [string map [list \[ {\[} \] {\]} \\ {\\}] $clock_driver]
		if { [ lsearch $all_clock_drivers $aux_clock_driver] >= 0 } {
			::octopus::display_message debug "<2> There is already a clock defined on $aux_clock_driver"
			continue
		}
		if { [string match "* $clock_driver *" " ${skip-clocks} "] > 0 } {
			::octopus::display_message info "User requested to skip defining a test clock on $clock_driver"
		} else {
			lappend all_clock_drivers $clock_driver
			::octopus::display_message info "Defining a test clock on $clock_driver"
			define_dft \
				test_clock \
				-name $clock_name \
				-domain multi_clock_domains_chains \
				-controllable \
				$clock_driver
		}
	}

	::octopus::display_message info "END Defining test clocks from SDC"
	::octopus::append_cascading_variables
}
# END
################################################################################


################################################################################
# BEGIN define_dft_test_signals
# This procedure is identical with define_dft of cadence but allows more objects to be specified
proc ::octopusRC::define_dft_test_signals args {

	# Find available timing modes
	set timing_modes ""
	foreach iii [find / -vname -mode *] {
		lappend timing_modes [file tail $iii]
	}

	set  help_head {
		::octopus::display_message none "Extracts set_case_analysis statements in a certain timing mode and add them as DfT constraints"
	}
	# Procedure options parsing
	::octopus::add_option --name "--timing-modes" --max "infinity" --valid-values "$timing_modes" --help-text "The timing mode(s) the set_case_analysis will be extracted from"
	::octopus::add_option --name "--skip-signals" --default "" --max "infinity" --help-text  "Skip the DfT constraints for the specified signal (not recommended)"
	::octopus::add_option --name "--add-signals" --default "" --max "infinity" --help-text "Add more DfT constraints then the one specified in the SDC constraints. (not recommended)"
	::octopus::add_option --name "--test-mode" --default "shift" --valid-values "shift capture" --help-text "The DfT mode the timing mode is associated with"

	extract_check_options_data ; #description of var_array variable is given in this procedures

	::octopus::abort_on error --return --display-help

	::octopus::display_message info "BEGIN Defining test signals from timing mode(s): ${timing-modes}"

	# Start processing all signals from SDC
	set all_signals ""
	# Check that all signals specified by add-signals are valid objects
	foreach crt_add_signal ${add-signals} {
		if { "${add-signals}" != "" && [catch {lappend all_signals [ls $crt_add_signal]} ] } {
			::octopus::display_message error "$crt_add_signal does not exist in the design"
		}
	}
	# Check that all signals specified by skip-signals are valid objects
	foreach crt_skip_signal ${skip-signals} {
		if { "${skip-signals}" != "" && [catch {lappend all_signals [ls $crt_skip_signal]} ] } {
			::octopus::display_message error "$crt_skip_signal does not exist in the design"
		}
	}

	::octopus::abort_on error --return

	if { "${test-mode}" == "shift" } {
		set ssc "-scan_shift"
	} else {
		set ssc ""
	}

	::octopus::display_message debug "<2> collecting set_case_analysis statements from RC database"
	set all_signals "$all_signals [filter timing_case_logic_value_by_mode {[^\s]+[\s]+[\d]} -regexp [concat [find / -pin *] [find / -port *]]]"
	set all_processed_signals ""

	foreach crt_timing_mode ${timing-modes} {
		foreach crt_sgn $all_signals {
			foreach crt_mode_value [get_attribute timing_case_logic_value_by_mode $crt_sgn] {
				set crt_mode 	[lindex $crt_mode_value 0]
				set crt_value 	[lindex $crt_mode_value 1]
				if { $crt_value == 1 } {
					set active high
				} else {
					set active low
				}
				if { "[file tail $crt_mode]" == "$crt_timing_mode" } {
					set aux_crt_sgn [string map [list \[ {\[} \] {\]} \\ {\\}] $crt_sgn]
					if { [ lsearch $all_processed_signals $aux_crt_sgn] >= 0 } {
						::octopus::display_message debug "<2> There is already a test_mode defined on $aux_crt_sgn"
						continue
					}
					set cdcv [get_attribute dft_constant_value $aux_crt_sgn]
					if { 	("$cdcv" == "high" || "$cdcv" == "low") && "$cdcv" != "$active" } {
						::octopus::display_message warning "RC database contains already a test_mode defined on ${aux_crt_sgn} with a different value being: '$cdcv'"
						::octopus::display_message debug "<2> Skipping definition of $aux_crt_sgn to $active for test-mode ${test-mode}"
						continue
					}
					if { [string match "* $crt_sgn *" " ${skip-signals} "] > 0 } {
						::octopus::display_message info "User requested to skip defining a test value on $crt_sgn"
						continue
					}
					lappend all_processed_signals $crt_sgn
					eval ::define_dft test_mode -active $active $ssc $crt_sgn
				}
			}
		}
	}
	::octopus::append_cascading_variables
}
# END
################################################################################


################################################################################
# BEGIN generate_list_of_clock_inverters_for_dft_shel
# This procedure Generate a hybrid list of inverters used for dft_shell.
# dft_shell cannot handle neg-edge clocked SFF's. Thus generate this list so
# that inverters can be modelled by buffers. Functionality is not the same, but
# thsi will allow dft_shell to continue other dft validation steps.
proc ::octopusRC::generate_list_of_clock_inverters_for_dft_shell args {

	::octopus::add_option --name ">" --default "stdout" --help-text "Redirects the output to a file"

	extract_check_options_data ; #description of var_array variable is given in this procedures

	::octopus::abort_on error --return --display-help

	::octopus::display_message info "Ignore the Errors from here"

	# Find the falling edge FF
	set fall_edge_ffs [filter dft_test_clock_edge "fall" [concat [filter flop "true" [find / -inst *]] dft/scan_segments/*] ]
	set last_clk_inverters ""
	::octopus::display_message debug "<2> List of falling edge flip-flops"
	foreach crt_ff $fall_edge_ffs {
		::octopus::display_message debug "<2> ================================================================================"
		::octopus::display_message debug "<2> $crt_ff"
		set prev_inversion "-"
		if { [catch {set clock_pin "[get_attribute clock $crt_ff]"} ] } {
			set clock_pin "${crt_ff}/pins_in/CP"
		}
		::octopus::display_message debug "<2> clock_pin=$clock_pin"
		foreach iii [fanin $clock_pin] {
			::octopus::display_message debug "<2> ---"
			set crt_inversion [lindex [lindex [get_attribute propagated_clocks $iii] 0] 3]
			if { "$crt_inversion" != "$prev_inversion"} {
				# There is a phase inversion record this instance
				::octopus::display_message debug "<2> Found the inverter: [vname $iii]"
				lappend last_clk_inverters [vname [file dirname [file dirname $iii] ]]
				# exit foreach loop since there is no need to continue
				break
			} else {
				::octopus::display_message debug "<2> $iii"
			}
			::octopus::display_message debug "<2> ---"
			set prev_inversion $crt_inversion
		}
		::octopus::display_message debug "<2> ================================================================================"
	}
	::octopus::display_message info "Ignore Errors to here"
	set last_clk_inverters [lsort -unique $last_clk_inverters]

	puts $redirect_fileId "set my_shift_inv_clk {"
	foreach iii $last_clk_inverters {
		regsub -all {/} $iii {.} jjj
		puts $redirect_fileId "	${jjj}.Z=\[P\]"
	}
	puts $redirect_fileId "}"

	puts $redirect_fileId ""
	puts $redirect_fileId "proc disconnect_inverter_ports { } {"
	foreach iii $last_clk_inverters {
		regsub -all {/} $iii {.} jjj
		puts $redirect_fileId "	disconnect_port -port ${jjj}.A"
	}
	puts $redirect_fileId "}"

	if { "$redirect" != "stdout" } {close $redirect_fileId}
	::octopus::append_cascading_variables
}
# END
################################################################################


################################################################################
# BEGIN 
### clock gating reporting procedure -- copied from an application note from Cadence sourcelink
proc ::octopusRC::report_cg_tree args {

	::octopus::add_option --name ">" --default "stdout" --help-text "Redirects the output to a file"

	extract_check_options_data ; #description of var_array variable is given in this procedures

	if {[llength [find / -design *]] < 1} {
		display_message error "There is no design loaded. Load the design and map it before running"
	}
	
	if {[llength [find . -design *]] > 1} {
		display_message error "There are multiple designs loaded."
		display_message " : [find / -design *]"
		display_message " : 'cd' to target design"
	}



	if {[llength [find . -design *]] == 1} {
		set sav_des [find . -design *]
	} else {
		set des_chk [pwd]
		if {[string match [what_is $des_chk] design]} {
			set sav_des [pwd]
		} else {
			display_message error "Only work from design vdir. 'cd' to top design"
		}
	}

	::octopus::abort_on error --return --display-help

	set sav_rc_cg_list [filter lp_clock_gating_rc_inserted true [find / -inst *]]
	puts $redirect_fileId "=============================================================="
	puts $redirect_fileId " Report Format Example "
	puts $redirect_fileId " ---------------"
	puts $redirect_fileId " CG-Inst top/m1/m2/RC_CG_HIER_INST1 -->"
	puts $redirect_fileId ""
	puts $redirect_fileId " Gated flops -- top/m1/m2/reg1"
	puts $redirect_fileId " -- top/m1/m2/reg2"
	puts $redirect_fileId " -- top/m1/reg3"
	puts $redirect_fileId ""
	puts $redirect_fileId "=============================================================="
	puts $redirect_fileId " RC INSERTED CG "
	puts $redirect_fileId "=============================================================="
	foreach sav_rc_cg $sav_rc_cg_list {
		puts $redirect_fileId "[vname $sav_rc_cg] -->"
		foreach sav_gff [get_attr lp_clock_gating_gated_flops $sav_rc_cg] {
			puts $redirect_fileId " -- [vname $sav_gff]"
		}
		puts $redirect_fileId " ----------------------------------------------------------"
	}
	puts $redirect_fileId ""
	puts $redirect_fileId "=============================================================="
	puts $redirect_fileId " NON-RC INSERTED CG "
	puts $redirect_fileId "=============================================================="
	cg_utl::get_non_rc_gated_cgs $sav_des sav_other_cg_list
	if {::octopus::debug_level >= 1} {
		puts $redirect_fileId "sav_other_cg_list = $sav_other_cg_list"
	}
	foreach sav_other_cg $sav_other_cg_list {
		set sav_other_gff_list [cg_utl::getGatedFlopsOfCG $sav_other_cg]
		puts $redirect_fileId "[vname $sav_other_cg] -->"
		foreach sav_other_gff $sav_other_gff_list {
			puts $redirect_fileId " -- [vname $sav_other_gff]"
		}
		puts $redirect_fileId " ----------------------------------------------------------"
	}

	if { "$redirect" != "stdout" } {close $redirect_fileId}
	display_message info "Clock-gating report generated!"
	::octopus::append_cascading_variables
}
# END
################################################################################


################################################################################
# BEGIN write
# procedure used to write in a more structural way relevant information about
# design
proc ::octopusRC::write args {

	::octopusRC::check_set_common_vars

	set  help_head {
		::octopus::display_message none "Write netlists, databases, lec, reports"
	}

	::octopus::add_option --name "--stage" --valid-values "rtl elb gen mapped mapped_scn syn inc_scn scn" --help-text "String specifying the design stage. It is used in file names."
	::octopus::add_option --name "--netlist-path" --default "${_NETLIST_PATH}" --help-text "Path were the netlist is written to."
	::octopus::add_option --name "--no-netlist" --default "false" --type "boolean" --help-text "Prevents writing the design netlist"
	::octopus::add_option --name "--no-lec" --default "false" --type "boolean" --help-text "Prevents writing out the lec do files"
	::octopus::add_option --name "--no-database" --default "false" --type "boolean" --help-text "Prevents writing the design database"
	::octopus::add_option --name "--no-reports" --default "false" --type "boolean" --help-text "Prevents writing any reports"
	::octopus::add_option --name "--change-names" --default "false" --type "boolean" --help-text "Allow only \"characters\", \"_\" and \"\[ \]\". Switch active only if a netlist is written out."
	::octopus::add_option --name "--rm-designs" --default "" --max "infinity" --help-text "Remove the specified modules before writing out netlist."
	::octopus::add_option --name "--design" --variable-name "DESIGN" --default "$DESIGN" --help-text "Top-Level design."
	::octopus::add_option --name "--reports-path" --variable-name "_REPORTS_PATH" --default "$_REPORTS_PATH" --help-text "Directory storage for the reports."

	extract_check_options_data

	::octopus::abort_on error --return --display-help

	set gdc "-golden_design ${netlist-path}/${DESIGN}_netlist_${::octopusRC::previous_stage}.v"
	set ntlst ${netlist-path}/${DESIGN}_netlist_${stage}.v
	set report_power "false"
	set report_timing "false"
	switch -- $stage {
		rtl {
			display_message fixme "Reports for RTL still to be defined"
			set gdc ""
		}
		gen {
			display_message fixme "gen needs some love"
		}
		mapped {
			display_message fixme "mapped needs some love"
		}
		mapped_scn {
			display_message fixme "mapped_scn needs some love"
		}
		syn {
			display_message fixme "Reports for SYN stage still to be defined"
		}
		inc_scn {
			display_message fixme "inc_scn needs some love"
		}
		scn {
			set report_power "true"
			set report_timing "true"
		}
	}

	# LEC scripts generation
	if { "${no-lec}" == "false" && "$::octopusRC::run_speed" != "fast"} {
		set lecdo "generated/${DESIGN}_do_lec_${::octopusRC::previous_stage}2${stage}.cmd"
		::octopus::display_message debug "<5> Writing lec do file : $lecdo "
		eval ::write_do_lec -hier $gdc -revised_design ${ntlst} > $lecdo
	}

	# Database writing
	if { "${no-database}" == "false" && "$::octopusRC::run_speed" != "fast"} {
		shell mkdir -p db
		::write_db ${DESIGN} -all_root_attributes -to_file db/${DESIGN}_${stage}.db
	}

	# Reports/check design/etc.
	if { "${no-reports}" == "false" && "$::octopusRC::run_speed" != "fast"} {
		set date [exec date +%s]
		::check_design -all > $_REPORTS_PATH/${DESIGN}_check_design_${date}.rpt
		if { "$report_power" == "true" } {
			set modes ""
			foreach iii [find / -mode *] {
				#lappend modes [file tail $iii]
				report power -verbose -power_mode [file tail $iii] > ${_REPORTS_PATH}/${DESIGN}_report_power_${iii}_${date}.rpt
			}
		}
		if { "$report_timing" == "true" } {
			set modes ""
			foreach iii [find / -mode *] {
				#lappend modes [file tail $iii]
				report timing -mode [file tail $iii] > ${_REPORTS_PATH}/${DESIGN}_report_timing_${iii}_${date}.rpt
			}
		}
	}

	if { "${rm-designs}" != "" } {
		foreach iii ${rm-designs} {
			foreach jjj [get_attribute instances [find / -subdes $iii]] {
				set_attribute preserve false [find $jjj -instance *]
				rm $jjj
			}
		}
	}

	# Netlist generation
	if { "${no-netlist}" == "false" } {
		::octopus::display_message debug "<5> Writing netlist: $ntlst "
		if { "${change-names}" == "true" } {
			::octopus::display_message debug "<5> Changing netlist names"
			set unpreserve [concat gt_ lt_ add_ geq_ leq_ abs_ csa_ sub_]

			foreach item $unpreserve {
				set gt [find / -subdesign ${item}*] 
				if { [llength $gt] > 0 } { set_attribute preserve false $gt}
			}
			change_names -allowed ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_\[\]
			change_names -restricted ":" -replace_str "_"  -subdesign -force ; # getting rid of : in csa_blocks
		}
		write_hdl >  $ntlst
	}

	set ::octopusRC::previous_stage ${stage}
	::octopus::append_cascading_variables
}
# END
################################################################################


################################################################################
# BEGIN elaborate
# procedure used to write in a more structural way relevant information about
# design
proc ::octopusRC::elaborate args {

	::octopusRC::check_set_common_vars

	::octopus::add_option --name "--design" --variable-name "DESIGN" --default "$DESIGN" --help-text "Top-Level design."
	::octopus::add_option --name "--reports-path" --variable-name "_REPORTS_PATH" --default "$_REPORTS_PATH" --help-text "Directory storage for the reports."
	extract_check_options_data
	::octopus::abort_on error --return --display-help

	::elaborate ${DESIGN}
	
	::octopus::design_crawler --tcb --tpr

	::octopusRC::write --stage elb --no-netlist --no-lec 

	::octopus::append_cascading_variables
}
# END
################################################################################


################################################################################
# BEGIN read_cpf
# procedure used to write in a more structural way relevant information about
# design
proc ::octopusRC::read_cpf args {

	::octopusRC::check_set_common_vars

	set  help_head {
		::octopus::display_message none "Reads the CPF file and does standard checks"
	}

	::octopus::add_option --name "--cpf" --help-text "CPF file"
	::octopus::add_option --name "--design" --variable-name "DESIGN" --default "$DESIGN" --help-text "Top-Level design."
	::octopus::add_option --name "--reports-path" --variable-name "_REPORTS_PATH" --default "$_REPORTS_PATH" --help-text "Directory storage for the reports."

	extract_check_options_data

	::octopus::abort_on error --return --display-help

	::read_cpf $cpf

	::octopus::display_message warning "Rumours say that displaying \$::dc::sdc_failed_commands might be wrong"
	puts $::dc::sdc_failed_commands

	foreach current_design_mode [ find / -vname -mode * ] {
		report timing -lint -verbose -mode [file tail $current_design_mode] >  ${_REPORTS_PATH}/${DESIGN}_report_timing_lint_${current_design_mode}.rpt
	}

	if { "$::octopusRC::run_speed" != "fast"} {
		set date [exec date +%s]
		check_library 		> ${_REPORTS_PATH}/${DESIGN}_check_library_${date}.rpt
		check_cpf -detail 	> ${_REPORTS_PATH}/${DESIGN}_check_cpf_${date}.rpt
		check_design -all 	> ${_REPORTS_PATH}/${DESIGN}_check_design_${date}.rpt
	}
	::octopus::append_cascading_variables
}
# END
################################################################################


################################################################################
# BEGIN synthesize
# procedure used to write in a more structural way relevant information about
# design
proc ::octopusRC::synthesize args {

	::octopusRC::check_set_common_vars

	set  help_head {
		::octopus::display_message none "Synthesize the design and writes out useful files: netlist, lec do, etc."
	}

	set  help_tail {
		::octopus::display_message none ""
	}

	::octopus::add_option --name "-to_generic" --type "boolean" --default "false" --help-text "-to_generic synthesize option from RC"
	::octopus::add_option --name "-to_mapped" --type "boolean" --default "false" --help-text "-to_mapped synthesize option from RC"
	::octopus::add_option --name "-incremental" --type "boolean" --default "false" --help-text "-incremental synthesize option from RC"
	::octopus::add_option --name "-no_incremental" --type "boolean" --default "true" --help-text "-incremental synthesize option from RC"
	::octopus::add_option --name "-effort" --default "automatic" -valid-values "automatic low medium high" --help-text "Synthesize effort, passed to the RC synthesize option."

	::octopus::add_option --name "--type" --default "obsolete" --valid-values "obsolete to_generic to_mapped to_mapped_incremental" --help-text "OBSOLETE option: Specify to synthesis type."
	::octopus::add_option --name "--netlist-path" --default "${_NETLIST_PATH}" --help-text "Path were the netlist is written to."
	::octopus::add_option --name "--design" --variable-name "DESIGN" --default "$DESIGN" --help-text "Top-Level design."
	::octopus::add_option --name "--reports-path" --variable-name "_REPORTS_PATH" --default "$_REPORTS_PATH" --help-text "Directory storage for the reports."

	extract_check_options_data

	::octopus::abort_on error --return --display-help

	if { "$type" != "obsolete" } {
		display_message error "--type option is obsolete. Do not use it anymore. Just use native RC options instead."
	}

	# exclusive options
	if {	"$to_generic" == "false" & \
		"$to_mapped" == "false" } {
		display_message error "At least one option of -to_generic or -to_mapped needs to be specified."
	}
	if {	"$to_generic" == "true" & \
		"$to_mapped" == "true" } {
		display_message error "Only one option of -to_generic or -to_mapped needs to be specified."
	}
	if {	"$-incremental" == "false" & \
		"$-no_incremental" == "false" } {
		display_message error "At least one option of --incremental or --no_incremental needs to be specified."
	}
	if {	"$-incremental" == "true" & \
		"$-no_incremental" == "true" } {
		display_message error "Only one option of --incremental or --no_incremental needs to be specified."
	}


	if {"$to_generic" == "true"} {set type "-to_generic"}
	if {"$to_mapped" == "true"} {set type "-to_mapped"}
	if {"$incremental" == "true"} {set type_incr "-incremental"}
	if {"$no_incremental" == "true"} {set type_incr "-no_incremental"}

	if {"$to_generic" == "true"} {
		set stage gen
	} elseif {"$to_mapped" == "true" & "$no_incremental" == "true"} {
		set stage mapped
	} elseif {"$to_mapped" == "true" & "$incremental" == "true"} {
		set stage inc_scn
	} else {
		display_message dev_error "Unhandled case."
	}

	::octopus::abort_on error --suspend --display-help

	# Specify the effort required for Generic Synthesis. It is recommended to
	# specify medium for Generic and non incremental synthesis for the first run
	if { "$effort" != "automatic" } {
		# do nothing effort already set.
	} elseif { 	"[get_attribute octopusRC_design_maturity_level]" == "pre-alpha" || \
			"[get_attribute octopusRC_design_maturity_level]" == "alpha"} {
		set effort medium
	} else {
		set effort high
	}

	::synthesize $type -effort $effort $type_incr

	::octopusRC::write --stage $stage --netlist-path ${netlist-path}

	::octopus::append_cascading_variables
}
# END
################################################################################


################################################################################
# BEGIN constraints_from_tcbs
# procedure used to constraints_from_tcbs based on the test data files of the TCB's'
proc ::octopusRC::constraints_from_tcbs args {

	::octopusRC::check_set_common_vars

	set  help_head {
		::octopus::display_message none "Extracts the TCB values from test-data file(s) in a specified test mode and writes out SDC constraints"
	}

	::octopus::add_option --name "--tcb-td-file" --max "infinity" --help-text "TCB test data file(s)"
	::octopus::add_option --name "--mode" --help-text "TCB mode from test data file for which constant values are extracted"
	::octopus::add_option --name "--exclude-ports" --default "" --max "infinity" --help-text  "Skip the specified TCB port(s) completely. No false paths/No constraints Not recommended)"
	::octopus::add_option --name "--ports" --default "" --max "infinity" --help-text "Only the specified ports are considered for set_case_analysis. For the remaining ports a false path constraint is added. If --ports is not specified, all TCB signals will be considered for set_case_analysis."
	::octopus::add_option --name "--no-false-paths" --default "false" --type "boolean" --help-text "No false paths are generated for the unconstrained TCB signals. (Not recommended)"
	::octopus::add_option --name "--constraint-file" --help-text "The name of the file where the constraints are written into"
	::octopus::add_option --name "--append" --default "false" --type "boolean" --help-text "Appends into <constraint-file> instead of truncating it"
	::octopus::add_option --name "--design" --variable-name "DESIGN" --default "$DESIGN" --help-text "Top-Level design."

	set  help_tail {
		::octopus::display_message none "Note:"
		::octopus::display_message none "--ports option is compulsory for design maturity higher than alpha, if the design is not in application mode."
		::octopus::display_message none "        The reason is that you might hide valid timing paths"
	}

	extract_check_options_data

	::octopus::abort_on error --return --display-help

	if { 	"[get_attribute octopusRC_design_maturity_level]" != "pre-alpha" && \
		"[get_attribute octopusRC_design_maturity_level]" != "alpha" && \
		"$ports" == "" && \
		"$mode" != "application" } { 
		display_message error "For [get_attribute octopusRC_design_maturity_level] maturity level the --ports option is compulsory. It is too risky to do synthesis with set_case_analysis on all TCB ports!. The test engineers tend to change the polarity of test signals even after tape-out."
	}

	if { "${append}" == "false" } {
		set ta "TRUNC"
	} else {
		set ta "APPEND"
	}

	if { [catch {set fileIDsdc [open ${constraint-file} "$ta WRONLY CREAT" 0640]} ] } {
		::octopus::display_message error "Cannot open ${constraint-file} file for writing."
		::octopus::append_cascading_variable
		return 1
	}
	if { "$append" == "true" } {
		puts $fileIDsdc "# Appended by ::octopusRC::constraints_from_tcbs procedure"
	} else {
		puts $fileIDsdc "# File created by [::octopus::calling_proc -1] procedure"
	}
	set date_time [exec date]
	puts $fileIDsdc "# on :: $date_time"

	# parse one file at a time
	foreach crt_file ${tcb-td-file} {
		puts $fileIDsdc ""
		if { [info exists cell] }	{ unset cell}
		if { [info exists effect] }	{ unset effect}
		if { [info exists tcbmode] }	{ unset tcbmode}
		set all_ports ""
		set all_ports_names ""
		if { [catch {set fileIDtcb [open $crt_file {RDONLY} ]} ] } {
			::octopus::display_message error "Cannot open $crt_file file for reading."
		} else {
			foreach line [split [read $fileIDtcb] "\{\}" ] {
				if { ! [info exists cell] } {
					regexp -nocase {[\s]*Cell[\s]+([^\s]+)} $line match cell
				} elseif { ! [info exists tcbmode ] } {
					regexp -nocase {[\s]*TcbMode[\s]+([^\s]+)} $line match tcbmode
				} elseif { ! [info exists effect ] } {
					regexp -nocase {[\s]*(Effect)[\s]+} $line match effect
				} elseif { [info exists tcbmode ] && "$tcbmode" != "$mode" } {
					# That's not the mode we are seraching for.
					# Unset the tcbmode to search the next tcbmode
					unset tcbmode
					unset effect
				} elseif { [info exists effect] } {
					foreach cpv [split $line ";"] {
						if { [ regexp -nocase {[\s]*([^\s]+)[\s]*=[\s]*\[([L|H])\]} $cpv match port value] } {
							if { "$value" == "H" } { set value_int 1 } else { set value_int 0 }
							lappend all_ports [list $port $value_int]
							lappend all_ports_names $port
							}
						}
					# found our mode so no need to continue parsing the file
					break
				}
			}
			if { "$all_ports" == "" } {
				display_message error "Mode $mode not found in $crt_file"
				continue
			}
			if { ! [info exists cell] } {
				display_message error "Could not find a cell in the test data file $crt_file"
				continue
			}
			set crt_subdes [find /des* -subdes $cell ]
			if { "$crt_subdes" == "" } {
				::octopus::display_message error "$cell does not exist in the design. Why do you still have a td file?" 
				continue
			}
			set instance_path [get_attribute instances $crt_subdes]
			display_message debug "<20> Instance path found: $instance_path of cell $cell"
			if { [llength $instance_path] >1 } {
				::octopus::display_message error "More than one TCB instantiation for $cell module has been found. Don't know what to td :-("
				continue
			}
			display_message debug "<5> Found TCB cell $cell in test data file $crt_file"
			display_message debug "<15> TCB ports and values of $cell in mode $mode: $all_ports"
			foreach aux $ports {
				if { [lsearch -exact ${all_ports_names} $aux ] == -1 } {
					display_message warning "$aux port not present in the TCB $cell picked from $crt_file"
				}
			}
			# Create constraints
			puts $fileIDsdc "################################################################################"
			puts $fileIDsdc "# 	TCB test data file: $crt_file"
			puts $fileIDsdc "# 	TCB mode: $mode"
			puts $fileIDsdc "# 	TCB excluded ports: ${exclude-ports} "
			puts $fileIDsdc "# 	TCB only ports: ${ports} "
			puts $fileIDsdc ""
			foreach cpv $all_ports {
				set crt_port 	[lindex $cpv 0]
				set crt_value 	[lindex $cpv 1]
				if { [lsearch -exact ${exclude-ports} $crt_port ] == -1 } {
					set full_path_fanin [vname [fanin -max_pin_depth 1 ${instance_path}/${crt_port}]]
					if { $full_path_fanin ==  1 } {
						::octopus::display_message error "Could not find ${instance_path}/${crt_port} in $DESIGN"
					} else {
						set gp_full_path_fanin "\[get_pins -nocase -regexp ${full_path_fanin}\]"
						if { [lsearch -exact ${ports}  $crt_port] != -1 || "$ports" == "" } {
							puts $fileIDsdc "#Derived from: ${crt_port} :: $crt_value"
							puts $fileIDsdc "set_case_analysis $crt_value ${gp_full_path_fanin}"
						} else {
							# port not in the list specified by the user. Are we allowed to have false-paths?
							puts $fileIDsdc "    # Derived from: ${crt_port} :: $crt_value"
							if { "${no-false-paths}" == "false" } {
								puts $fileIDsdc "    set_false_path -through ${gp_full_path_fanin}"
							} else {
								puts $fileIDsdc "    # False path disabled by user => SKIPPING port: $crt_port"
							}
						}
					}
				} else {
					puts $fileIDsdc "# SKIPPING user requested port: $crt_port"
				}
			}
			puts $fileIDsdc "################################################################################"

			if { [info exists cell] } 	{unset cell}
			if { [info exists tcbmode] } 	{unset tcbmode}
			if { [info exists effect] } 	{unset effect}
			close $fileIDtcb
		}
	}
	close $fileIDsdc
	::octopus::append_cascading_variable
}
# END
################################################################################


################################################################################
# BEGIN read_hdl
# Procedure used to read in files based on various file lists
proc ::octopusRC::read_hdl args {

	global env

	set  help_head {
		::octopus::display_message none "Reads in RTL files based on certain types of file lists"
		::octopus::display_message none "currently only rc and utel file list are supported"
	}

	::octopus::add_option --name "--file" --max "infinity" --help-text "File(s) containing the list with all RTL to be read"
	::octopus::add_option --name "--type" --valid-values "text utel rc" --help-text "Type of file to read in"
	::octopus::add_option --name "--skip-files" --default "" --max "infinity" --help-text "Skip the file(s). E.g. interfaces/behaviour/etc. Should be exactly the same as specified in 'file'"
	extract_check_options_data

	::octopus::abort_on error --return --display-help

	set file_set_total [::octopus::parse_file_set --type $type --file $file]

	foreach x $file_set_total {
		foreach { f t l o } $x {
			if { ! [ string match "*[subst $f]*" ${skip-files} ] } {
				case $t in {
				"verilog" {
					eval ::read_hdl -v2001 $f -library $l
					}
				"vhdl" {
					eval ::read_hdl -vhdl $f -library $l
					}
				}
			} else {
				display_message debug "<2> Skipping reading in $f file at request of the user"
			}
		}
	}

	::octopus::append_cascading_variables
}
# END
################################################################################


################################################################################
# BEGIN delete_unloaded_undrive
# Procedure used to skip the delete_unloaded_undriven for early designs
proc ::octopusRC::delete_unloaded_undriven args {

	::octopusRC::check_set_common_vars

	set  help_head {
		::octopus::display_message none "Deletes the unloaded and undriven. Depending on the design maturity this command is activated or not"
	}
	::octopus::add_option --name "--design" --variable-name "DESIGN" --default "$DESIGN" --help-text "Top-Level design."
	extract_check_options_data


	if { 	"[get_attribute octopusRC_design_maturity_level]" != "pre-alpha" && \
		"[get_attribute octopusRC_design_maturity_level]" != "alpha"} {
		::delete_unloaded_undriven -all -force_bit_blast ${DESIGN}
	} else {
		display_message info "Skiping delete_unloaded_undriven due to the maturity of the design: [get_attribute octopusRC_design_maturity_level]"
	}

	::octopus::append_cascading_variables
}
# END
################################################################################


################################################################################
# BEGIN check_set_common_vars
# This ugly procedure sets the DESIGN/_REPORTS_PATH variable at the calling procedure to <none> or to
# the top-level values.
proc ::octopusRC::check_set_common_vars args {

	foreach crt_var "DESIGN _REPORTS_PATH _NETLIST_PATH" {
		set cmd [list uplevel #0 [list catch [list set $crt_var]]]

		if { [eval $cmd ] } {
			display_message debug "<10> Setting $crt_var to <none>"
			set cmd [list uplevel [list set $crt_var "<none>"]]
			eval $cmd
		} else {
			set tl_var [uplevel #0 "set $crt_var"]
			display_message debug "<10> Setting $crt_var to $tl_var"
			set cmd [list uplevel [list set $crt_var $tl_var]]
			eval $cmd
		}
	}
	::octopus::append_cascading_variables
}
# END check_set_common_vars
################################################################################


################################################################################
# BEGIN check_set_common_vars
proc ::octopusRC::clean_reports args {

	::octopusRC::check_set_common_vars

	::octopus::add_option --name "--no-save" --default "false" --type "boolean"  --help-text "Do not preserve the old reports"
	::octopus::add_option --name "--reports-path" --variable-name "_REPORTS_PATH" --default "$_REPORTS_PATH" --help-text "Directory storage for the reports."
	extract_check_options_data

	if { "${no-save}" == "false" } {
		catch {file delete -force [glob -nocomplain ${_REPORTS_PATH}_previous_run]}
		catch {file rename $_REPORTS_PATH ${_REPORTS_PATH}_previous_run}
		catch {file copy -force rc.log ${_REPORTS_PATH}_previous_run/}
		catch {file copy -force rc.cmd ${_REPORTS_PATH}_previous_run/}
	}
	file mkdir ${_REPORTS_PATH}
	::octopus::append_cascading_variables
}
# END check_set_common_vars
################################################################################


################################################################################
# BEGIN Find CCB output clock driver
proc ::octopusRC::output_driver args {

	global env

	set  help_head {
		::octopus::display_message none "Returns the list of drivers of the ports specified."
	}

	::octopus::add_option --name "--modules" --max "infinity" --help-text "List of module(s) in the design."
	::octopus::add_option --name "--pins" --help-text "The output port(s). Will be used to find the driver."
	extract_check_options_data

	::octopus::abort_on error --return --display-help

	set lod ""
	foreach iii ${modules} {
		if { [catch {set all_inst [get_attribute instances $iii]}]} {
			display_message warning "No instantiation of $iii"
		} else {
			foreach jjj $all_inst {
				foreach pin $pins {
					if { [llength [ls ${jjj}/pins_out/${pin} > /dev/null ] ] == 1 } {
						display_message error "${jjj}/pins_out/${pin} not found"
					} else {
						lappend lod [vname [fanin ${jjj}/pins_out/${pin} -max_pin_depth 1]]
					}
				}
			}
		}
	}
	::octopus::append_cascading_variables
	return $lod
}
# END
################################################################################


################################################################################
# BEGIN reprot timing between arbitrary ports in the design
proc ::octopusRC::report_timing args {

	set  help_head {
		::octopus::display_message none "Extracts the port name of the clock gate inside the CCB's"
	}

	::octopus::add_option --name "--from" --max "infinity" --help-text "Reports timing from any port in the design"
	::octopus::add_option --name "--to" --max "infinity" --help-text  "Report timing to any port in the design."
	::octopus::add_option --name ">" --default "stdout" --help-text "Redirects the output to a file"

	extract_check_options_data


	if { "$from" == "" && "$to" == "" } {
		display_message error "At least --from or --to needs to be specified"
	}

	set redirect_cmd ""
	if { "$redirect" != "stdout" } {
		set redirect_cmd ">> $redirect"
		file delete $redirect
	} 

	::octopus::abort_on error --return --display-help
	
	display_message debug "<10> report timing"
	foreach jjj "from to" {
		set ${jjj}_fil ""
		set ${jjj}_cmd ""
		if { [set $jjj] != "" } {
			foreach iii [set $jjj] {
				set fo [fanout -endpoints [set $jjj] ]
				if { $fo == 1 } {
					display_message error "No fanout found for $iii" 
				} else {
					set ${jjj}_fil [concat [set ${jjj}_fil] $fo ]
				}
			}
			set ${jjj}_fil [filter_valid_objects $jjj [set ${jjj}_fil]]
			set ${jjj}_cmd "-${jjj} [set ${jjj}_fil]"
			display_message debug "<10> $jjj $from"
		} 	
	}

	eval echo "from: $from" $redirect_cmd
	eval echo "to: $to" $redirect_cmd
	eval echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++" $redirect_cmd
	eval ::report timing $from_cmd $to_cmd $redirect_cmd

	::octopus::append_cascading_variables
}

proc filter_valid_objects {direction objects} {

	set cmd "::report timing -${direction} $objects > /dev/null"
	if { [eval $cmd] == 1 } {
		# failed command 
		if { [llength $objects] > 1 } {
			# Try lower half of the objects 
			set new_objects_low [ filter_valid_objects $direction [lrange $objects 0 [expr int([llength $objects]/2) - 1 ]]]
			if {  $new_objects_low == "" } {
				# we have found the culprit. Exclude this from list of objects
				set new_objects_low ""
			} 
			# Try the other half of the objects
			set new_objects_high [ filter_valid_objects $direction [lrange $objects [expr int([llength $objects]/2)] end]]
			if { $new_objects_high ==  "" } {
				set new_objects_high ""
			}
			eval return $new_objects_low $new_objects_high
		}
	} else {
		# Return list of valid 
		return $objects
	}

}
# END
################################################################################


################################################################################
# BEGIN return a list with all FF's and scan segements clocked on falling edge
proc ::octopus::find_fall_edge_objects args {
	set  help_head {
		::octopus::display_message none "Find all FF's and scan segements clocked on falling edge of the clock"
	}

	set ff_fall_edge_no_dft_part_of_segment [filter -invert dft_part_of_segment "*" [filter dft_test_clock_edge "fall" [filter flop "true" [find / -inst *]] ] ]
	set ff_fall_edge____dft_part_of_segment [filter         dft_part_of_segment "*" [filter dft_test_clock_edge "fall" [filter flop "true" [find / -inst *]] ] ]
	foreach jjj $ff_fall_edge____dft_part_of_segment {
		foreach iii [find / -scan_segment *] {
			if { [string match "* $jjj *" " [get_attribute elements $iii] "] } {
				lappend sg_fall_edge $iii
				break
			}
		}
	}
	if { [info exists sg_fall_edge] } {
		set sg_fall_edge [lsort -unique $sg_fall_edge]
	} else {
		set sg_fall_edge ""
	}
	return [lappend sg_fall_edge $ff_fall_edge_no_dft_part_of_segment]
}
# END
################################################################################


################################################################################
# BEGIN 
proc ::octopus::design_crawler args {

	upvar diehardus::TCBs(module) TCBs 
	upvar diehardus::TPRs(module) TPRs 
	upvar diehardus::lefs lefs 
#	upvar diehardus::ctls ctls 

	set  help_head {
		::octopus::display_message none "Help the user filling the design specific information"
	}

	::octopus::add_option --name "--tcb" --type "boolean" --default "false" --help-text "Search for TCB's in the design and sets the TCBs(module) variable"
	::octopus::add_option --name "--tpr" --type "boolean" --default "false" --help-text "Search for TPR's in the design and sets the TCBs(module) variable"
	::octopus::add_option --name "--lef" --type "boolean" --default "false" --help-text "Search for lef files"
	::octopus::add_option --name "--ctl" --type "boolean" --default "false" --help-text "Search for ctl files"
	::octopus::add_option --name "--scan-inputs" --default "si*" --help-text "Search for scan inputs, based on the name provided by the user."
	extract_check_options_data
	::octopus::abort_on error --return --display-help

	if { "$tcb" == "true" && ! ([info exist TCBs]  && $TCBs != "")} {set TCBs [find /designs -subdesign *tcb*]}
	if { "$tpr" == "true" && ! ([info exist TPRs]  && $TPRs != "")} {set TPRs [find /designs -subdesign *_tpr*]}
	if { "$lef" == "true" && ! ([info exist lefs]  && $lefs != "") } {display_message warning "--lef option not implemented"}
	if { "$ctl" == "true" && ! ([info exist ctls]  && $ctls != "") } {display_message warning "--ctl option not implemented"}

	display_message debug "<2> Found TCB's: $TCBs"
	display_message debug "<2> Found TPR's: $TPRs"

	foreach crt_var "TCBs TPRs" {
		if {"[set $crt_var]" == ""} {set $crt_var "diehardus_dummy_module"}
	}

	::octopus::append_cascading_variables
}
# END
################################################################################


################################################################################
# BEGIN lefs
# Returns a list with all lef files found under a certain directory level. it searches for *.lef files
#proc ::octopusRC::more_files_available args {
#
#	set var_array(10,directories) 			[list "--directories" "<none>" "string" "1" "infinity" "" "The directories for which we search for lef files." ]
#	set var_array(20,pattern)			[list "--pattern" "*.lef" "string" "1" "infinite" "" "File pattern to search for." ]
#
#	extract_check_options_data ; #description of var_array variable is given in this procedures
#	::octopus::display_message debug  "<1> Entering: $parrent_instance"
#
#	display_message error "Procedure [::octopus::calling_proc -1] not implemented"
#	::octopus::abort_on error --return --display-help
#
#	findFiles $directories $extension
#
#}
# END lefs
################################################################################


################################################################################
# BEGIN
proc ::octopusRC::report_power_over_area args {

	set  help_head {
		::octopus::display_message none "Returns a list with power, area and power/area numbers of the selected instances."
	}

	::octopus::add_option --name "--root" --default "/" --max "infinity" --help-text "The directories where the instances are searched"
	::octopus::add_option --name "--max-depth" --default "infinity" --help-text "Max depth of the search"
	::octopus::add_option --name "--min-depth" --default "0" --type "number" --help-text "Min depth of the search"
	::octopus::add_option --name "--csv" --default "stdout" --help-text "The name of comma separated file. stdout will mean 'on-screen'"

	set  help_tail {
		::octopus::display_message info "More information:"
		::octopus::display_message none "    RC has powerful filtering engines. You can use that to pass the instances that you need to this procedure"
		::octopus::display_message none "    e.g.: \[filter -invert lp_internal_power 0.000000 \[filter libcell * \[find / -inst *\]\]\]"
		::octopus::display_message none "      will get all libcells for which internal power is not zero."
	}

	extract_check_options_data

	if { "$csv" != "stdout" } {
		if { [catch {set fd [open ${csv} w 0640] } error ] } {
			display_message error "$error"
		}
	} else {
		set fd stdout
	}

	set jjj "/designs/*"
	set all_power [expr [get_attribute lp_internal_power $jjj] + [get_attribute lp_net_power $jjj] + [get_attribute lp_leakage_power $jjj]]
	set all_area  [get_attribute cell_area $jjj]

	::octopus::abort_on error --return --display-help

	puts $fd "Instance, Leakage Power, Internal Power, Net Power, Internal/Net, Power,%of total power,Area,% of total area, Power/Area,"
	set ipw ""
	foreach iii $root {
		if { [catch {get_attribute libcell $iii} ] || "[get_attribute libcell $iii]" == "" && ${max-depth} > 0 } {
			set all_instances [find $iii -maxdepth ${max-depth} -mindepth ${min-depth} -inst *]
		} else {
			set all_instances $iii
		}
		foreach jjj $all_instances {
			set jjj_pi [get_attribute lp_internal_power $jjj]
			set jjj_pn [get_attribute lp_net_power $jjj]
			set jjj_pl [get_attribute lp_leakage_power $jjj]

			if { $jjj_pn != 0 } {
				set jjj_piOpn [expr double(int(1000*$jjj_pi/$jjj_pn))/1000]
			} elseif {$jjj_pi == 0 }  {
				set jjj_piOpn 0
			} else {
				display_message warning "Net power of $jjj is zero."
				set jjj_piOpn infinite
			}

			set jjj_p [expr $jjj_pi + $jjj_pn + $jjj_pl]
			set jjj_ppct [expr double(int($jjj_p*1000000/$all_power))/10000]
			set jjj_a [get_attribute cell_area $jjj]
			set jjj_apct [expr double(int($jjj_a*1000000/$all_area))/10000]
			if { $jjj_a != 0 } {
				set jjj_pOa [expr $jjj_p/$jjj_a]
			} elseif {$jjj_p == 0 }  {
				set jjj_pOa 0
			} else {
				display_message warning "Area of cell $jjj is zero. Power over area number will be set to infinite"
				set jjj_pOa infinite
			}
			set jjj_name [vname $jjj]
			#lappend ipw [list $jjj_name $jjj_pl $jjj_pi $jjj_pn $jjj_piOpn $jjj_p $jjj_ppct $jjj_a $jjj_apct $jjj_pOa $jjj_pl $jjj_pi $jjj_pn $jjj_piOpn]
			puts $fd "$jjj_name,$jjj_pl,$jjj_pi,$jjj_pn,$jjj_piOpn,$jjj_p,$jjj_ppct,$jjj_a,$jjj_apct,$jjj_pOa"
		}
	}
	flush $fd
	if { "$csv" != "stdout" } { close $fd }
	#return  $ipw
}
#
# END 
################################################################################
