#
#    octopusRC: RTL Compiler package of useful procedures
#    Copyright (C) 2012 Octavian Petre <octavsly@gmail.com>.
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
}


################################################################################
# BEGIN set_design_maturity_level
# This procedure sets the maturity level of the design and sets attributes from the specified --rc-attributes-file
proc ::octopusRC::set_design_maturity_level args {

	set var_array(10,maturity-level)	[list "--maturity-level" "diamond" "string" "1" "1" "pyrite bronze silver gold diamond" "Specify the maturity level of the design."]
	set var_array(20,rc-attributes-file)	[list "--rc-attributes-file" "rc_attributes.txt" "string" "1" "infinity" "" "Specify the file from which settings will be extracted."]

	extract_check_options_data ; #description of var_array variable is given in this procedures

	set  help_head {
		::octopus::display_message none "Set the RC parameters based on the design maturity level"
	}

	::octopus::abort_on error --return --display-help

	::octopus::display_message info 	"Setting design maturity level to ${maturity-level}"
	::octopus::display_message warning "maturity level setting is in ALPHA stage"

	# Nice feature of RC, allowing user defined attributes
	define_attribute \
		octopusRC_design_maturity_level \
		-category user \
		-obj_type root \
		-data_type string \
		-default_value ${maturity-level} \
		-help_string "Define the maturity level of the design. Can be pyrite, bronze, silver, gold or diamond."

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
				rc_attribute value(pyrite) value(bronze) value(silver) value(gold) value(diamond) comment ] } {
				::octopus::display_message debug "<2> set_attribute $rc_attribute $value(${maturity-level})"
				if { "$value(${maturity-level})" != "-" } {
					set_attribute $rc_attribute $value(${maturity-level})
				}
				if { ${rc_attribute} == "hdl_track_filename_row_col" } {
					::octopus::display_message warning "hdl_track_filename_row_col attribute is known to create problems like slow-down and crashes"
				}
			}
		}
		close $fileID
	}

	set synthesis_effort(pyrite)	medium
	set synthesis_effort(bronze)	high
	set synthesis_effort(silver)	high
	set synthesis_effort(gold)	high
	set synthesis_effort(diamond)	high

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

	set var_array(max_level) 	[list "--max_level" "infinity" "string" "1" "1" "" ]
	set var_array(module_name) 	[list "--module_name" "<none>" "string" "1" "1" "" ]
	extract_check_options_data ; #description of var_array variable is given in this procedure
	::octopus::display_message error "Procedure not implemented"
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

	set var_array(10,group-children-of-instances)	[list "--group-children-of-instances" "<none>" "string" "1" "1" "" "Group all children of the specified instance(s)" ]
	set var_array(30,exclude-parents-of-instances) 	[list "--exclude-parents-of-instances" "<none>" "string" "1" "1" "" "During grouping exclude all parent of the specified instance(s)" ]

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

	set var_array(05,max-depth) 			[list "--max-depth" "infinite" "number" "1" "1" "" "Maximum logic depth the trace should. Currently only 1 level is implemented." ]
	set var_array(10,pin)				[list "--pin" "<none>" "string" "1" "infinite" "" "Pin name with full cadence path, vname or not." ]
	set var_array(20,fan)				[list "--fan" "<none>" "string" "1" "1" "in out" "Type of fan."]
	set var_array(30,vname)				[list "--vname" "false" "boolean" "0" "0" "" "Return the string is vname format" ]
	set var_array(40,include-nets)			[list "--include-nets" "false" "boolean" "0" "0" "Include nets during the traces. If this option is omitted, only ports are returned."]

	extract_check_options_data ; #description of var_array variable is given in this procedures
	::octopus::display_message debug  "<1> Entering: $parrent_instance"

	if { $max_depth > 1 } {
		::octopus::display_message error "--max_depth > 1 is not yet implemented"
	} else {
		set max_depth 1
	}

	::octopus::abort_on error --return --display-help

	set stop_at [fan${fan} -max_pin_depth $max_depth $pin]
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
	upvar include_nets include_nets
	upvar vname vname
	if { "$include_nets" == "true" } {
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
	upvar include_nets include_nets

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
	return [concat [include_nets $net] $accumulate_ports]
}
# END fanin_hierarchical
################################################################################


################################################################################
# BEGIN report_attributes
proc ::octopusRC::report_attributes args {

	set var_array(10,objects)	[list "--objects" "<none>" "string" "1" "infinity" "" "RC objects for which we want to return a list of attributes. Most likely objects found by \[find / -<type> <search>\]" ]
	set var_array(20,attributes) 	[list "--attributes" "<none>" "string" "1" "infinity" "" "Any valid object attribute, such as load/driver/etc." ]
	set var_array(30,redirect) 	[list ">" "stdout" "string" "1" "1" "" "Redirects the output to a file" ]

	extract_check_options_data ; #description of var_array variable is given in this procedures

	::octopus::abort_on error --return --display-help

	if { "$redirect" != "stdout" } {
		set fd [open ${redirect} w 0640]
	} else {
		set fd stdout
	}

	puts -nonewline $fd "Instance"
	foreach crt_att $attributes {
		puts -nonewline $fd " :${crt_att}: "
	}
	puts $fd ""
	puts $fd "================================================================================"

	# Sometimes the user uses a find command which returns the result with {}
	foreach iii [split "${objects}" " \{\}"] {
		if { "$iii" != "" } {
			puts -nonewline $fd "[vname $iii]"
			foreach crt_attr $attributes {
				catch {puts -nonewline $fd " :[file tail [get_attribute $crt_attr $iii]]: "}
			}
			puts $fd ""
		}
	}
	puts $fd "================================================================================"
	if { "$redirect" != "stdout" } { close $fd }
	::octopus::append_cascading_variables
}
# END report attributes
################################################################################


################################################################################
# BEGIN set_attribute_recursive
proc ::octopusRC::set_attribute_recursive args {

	set var_array(10,attribute)				[list "--attribute" "<none>" "string" "2" "2" "" "Specify the attribute to be applied. Format is attribute <true|false>."]
	set var_array(30,objects)				[list "--objects" "<none>" "string" "1" "infinity" "" "Specify the objects for which the attributes will beapplied. e.g. instaces/modules/pins/etc."]
	set var_array(40,direction)				[list "--direction" "down" "string" "1" "1" "up down both" "Specify the direction of recursion. up: all parents will get the attribute, down: all children. both:"]

	extract_check_options_data ; #description of var_array variable is given in this procedures

	::octopus::abort_on error --return --display-help

	set help_tail {
		::octopus::display_message none "More information:"
		::octopus::display_message none "    --objects:   While pins, or other projects, can be specified, it makes no sense, since recursion is not yet implemented"
	}

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
	foreach iii [find / -vname -mode *] {
		lappend timing_modes [file tail $iii]
	}

	set var_array(10,timing-modes)	[list "--timing-modes" "<none>" "string" "1" "infinity" "$timing_modes" "The timing mode(s) the clocks will be extracted from" ]
	set var_array(20,skip-clocks)	[list "--skip-clocks" "false" "string" "1" "infinity" "" "Skip the clocks specified in the constraints" ]
	set var_array(30,add-clocks)	[list "--add-clocks" "false" "string" "1" "infinity" "" "Add more clocks then the one specified in the constraints" ]

	extract_check_options_data ; #description of var_array variable is given in this procedures

	::octopus::abort_on error --return --display-help

	::octopus::display_message info "BEGIN Defining test clocks from SDC"

	set all_clocks ""
	# Check that all clocks specified by add-clocks is a valid object
	foreach crt_add_clock ${add-clocks} {
		if { "${add-clocks}" != "false" && [catch {lappend all_clocks [ls $crt_add_clock]} ] } {
			::octopus::display_message error "$crt_add_clock does not exist in the design"
		}
	}
	foreach crt_skip_clock ${skip-clocks} {
		if { "${skip-clocks}" != "false" && [catch {lappend all_clocks [ls $crt_skip_clock]} ] } {
			::octopus::display_message error "$crt_skip_clock does not exist in the design"
		}
	}

	::octopus::abort_on error --return

	set all_clocks "$all_clocks [find /*/*/modes/*/clock_domains/*/ -clock *]"

	set all_clock_drivers ""
	foreach crt_timing_mode ${timing-modes} {
		foreach crt_clock "$all_clocks" {
			set clock_name [file tail $crt_clock]
			if { [catch {set clock_driver [get_attribute non_inverted_sources $crt_clock]} ] } {
				::octopus::display_message error "Is $crt_clock a clock signal?"
			}
        		set aux_clock_driver [string map [list \[ {\[} \] {\]} \\ {\\}] $clock_driver]
		        if { [ lsearch $all_clock_drivers $aux_clock_driver] >= 0 } {
				::octopus::display_message debug "<2> There is already a clock defined on $aux_clock_driver"
                		continue
		        }
			if { [string match "* $clock_driver *" " ${skip-clocks} "] > 0 } {
				::octopus::display_message info "User requested to skip defining a test clock on $clock_driver"
			}
	        	lappend all_clock_drivers $clock_driver
			::octopus::display_message info "Defining a test clock on $clock_driver"
		        eval uplevel #0 {define_dft \
        	        	test_clock \
	                	-name $clock_name \
		                -domain multi_clock_domains_chains \
		                -controllable \
				$clock_driver}
		}
	}
	::octopus::display_message info "END Defining test clocks from SDC"
	::octopus::append_cascading_variables
}
# END
################################################################################


################################################################################
# BEGIN read_dft_abstract_model.
# This function already exists in cadence, thus is not exported.
proc ::octopusRC::read_dft_abstract_model args {

	set var_array(10,ctl)				[list "--ctl" "<none>" "string" "1" "infinity" "" "Specify the CTL file(s) to be read in. If --module option is used then only one file can be read in" ]
	set var_array(20,assume-connected-shift-enable)	[list "--assume-connected-shift-enable" "false" "boolean" "" "" "" "Specify this option if the shift enable is already connected for all CTL files read in." ]
	set var_array(30,module)			[list "--module" "" "string" "1" "1" "" "Specify the module/library cell associated with the ctl file. If missing 'Environment' CTL keyword will be used instead." ]
	set var_array(40,boundary-opto)			[list "--boundary-opto" "false" "boolean" "" "" "" "By default, boundary optimization is switched off for modules with CTL associated. By specifying this option you switch boundary optimization on" ]

	extract_check_options_data ; #description of var_array variable is given in this procedures

	::octopus::abort_on error --return --display-help

	if { "$module" != "" && [llength $ctl] > 1 } {
			::octopus::display_message error "If you specify --module option, then only one CTL file can be specified"
	}

	abort_on error --return --display-help

	if { "${assume-connected-shift-enable}" == "true"} {
		set assume_connected_shift_enable "-assume_connected_shift_enable"
	} else {
		set assume_connected_shift_enable ""
	}

	foreach crt_ctl_file $ctl {
		set crt_module ""
		if { "$module" != "" } {
			# Module(s) specified at command line. Thus do not find the Environment CTL keyword
			set crt_module $module
		} else {
			# No module specified, thus search for Environment keyword in CTL
			set fileID [open $crt_ctl_file {RDONLY} ]
			foreach line [split [read $fileID] "\{\}"] {
				# Process line
				if { [ regexp {.*Environment[\s]+[\"\']*([^\"\']*)[\"\']*[\s]*} $line match crt_module ] } {
					# Found the crt_module, just exit
					::octopus::display_message debug "<2> Extracted module '$crt_module' from CTL file '$crt_ctl_file'"
					break
				}
			}
			close $fileID
		}

		::octopus::display_message debug "<1> BEGIN Defining DfT abstract segments for all instances of module '${crt_module}'"
		if { [llength [lindex [find / -libcell ${crt_module}] 0]] !=0 } {
			# This is a library cell with scan-chains inside. e.g. AMOS does that to increase coverage
			#
			# Also search for unresolved. This should not be done but beacuse the powers are connected in RTL and because
			# the pg_pin attribute is in the library, RC cannot link the RTL instantiation with the library cell.
			# There is an option "set disable_power_ground_pin_support 0", but this makes RC < 10.10.300 crash
			set library_instantiations [filter libcell "[lindex [find -libcell $crt_module] 0]" [find / -inst * ] ]
			set unresolved_instantiations [filter subdesign "/designs/*/subdesigns/$crt_module" [filter unresolved true [find /designs -inst *] ] ]
			set instances [concat $library_instantiations $unresolved_instantiations ]
			foreach crt_instance $instances {
				eval uplevel #0 {read_dft_abstract_model \
					-segment_prefix "[file tail ${crt_module}]=[file tail ${crt_instance}]++" \
					-instance $crt_instance \
					$assume_connected_shift_enable \
					-ctl $crt_ctl_file }
			}
			if { [ llength $instances ] == 0 } {
					::octopus::display_message error "There is no instantiation of module ${crt_module}. Was this optimized away?"
			}
			if { [llength $unresolved_instantiations] != 0  } {
				::octopus::display_message warning "I am defining a chain on an unresolved instance: $unresolved_instantiations."
				::octopus::display_message warning "		 Check why it's unresolved."
				::octopus::display_message warning "		 Furthermore, this might create problems with the connect_scan_chains command since the scan-in/scan-out ports are preserved true and cannot be connected to the scan chain"
			}
		} else {
			# This is a cell
			set full_path_crt_module [find -subdesign ${crt_module}]
			if { [llength $full_path_crt_module] == 0 } {
				::octopus::display_message error "There is no instantiation of module ${crt_module}. Was it optimized away?"
			} else {
				if { "${boundary-opto}" == "false" } {
					::octopus::display_message debug "<2> Switching off boundary optimization for module $full_path_crt_module"
					set_attribute boundary_opto false  $full_path_crt_module
				}
				set iii 0
				foreach crt_instance [get_attribute instances $full_path_crt_module] {
					eval uplevel #0 {read_dft_abstract_model \
						-segment_prefix "[file tail ${crt_module}]=[file tail ${crt_instance}]++${iii}" \
						-instance $crt_instance \
						$assume_connected_shift_enable \
						-ctl $crt_ctl_file }
					incr iii
				}
			}
		}
		::octopus::display_message debug "<1> END Defining DfT abstract segments for all instances of module '${crt_module}'"
	}
	::octopus::append_cascading_variables
}
# END read_dft_abstract_model
################################################################################


################################################################################
# BEGIN define_dft_test_signals
# This procedure is identical with define_dft of cadence but allows more objects to be specified
proc ::octopusRC::define_dft_test_signals args {

	# Find available timing modes
	foreach iii [find / -vname -mode *] {
		lappend timing_modes [file tail $iii]
	}

	# Procedure options parsing
	set var_array(10,timing-modes)	[list "--timing-modes" "<none>" "string" "1" "infinity" "$timing_modes" "The timing mode(s) the set_case_analysis will be extracted from" ]
	set var_array(20,skip-signals)	[list "--skip-signals" "false" "string" "1" "infinity" "" "Skip the signal specified in the constraints (not recommended)" ]
	set var_array(30,add-signals)	[list "--add-signals" "false" "string" "1" "infinity" "" "Add more signals then the one specified in the constraints. (not recommended)" ]
	set var_array(40,test-mode)	[list "--test-mode" "shift" "string" "1" "1" "shift capture" "The DfT mode the timing mode is associated with"]

	extract_check_options_data ; #description of var_array variable is given in this procedures

	set  help_head {
		::octopus::display_message none "Extracts DfT constraints from SDC set_case_analysis statements"
	}

	::octopus::abort_on error --return --display-help

	::octopus::display_message info "BEGIN Defining test signals from timing mode(s): ${timing-modes}"

	# Start processing all signals from SDC
	set all_signals ""
	# Check that all signals specified by add-signals are valid objects
	foreach crt_add_signal ${add-signals} {
		if { "${add-signals}" != "false" && [catch {lappend all_signals [ls $crt_add_signal]} ] } {
			::octopus::display_message error "$crt_add_signal does not exist in the design"
		}
	}
	# Check that all signals specified by skip-signals are valid objects
	foreach crt_skip_signal ${skip-signals} {
		if { "${skip-signals}" != "false" && [catch {lappend all_signals [ls $crt_skip_signal]} ] } {
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
					if { [string match "* $crt_sgn *" " ${skip-signals} "] > 0 } {
						::octopus::display_message info "User requested to skip defining a test value on $crt_sgn"
					}
					lappend all_processed_signals $crt_sgn
					eval uplevel #0 {define_dft test_mode -active $active $ssc $crt_sgn}
				}
			}
		}
	}
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

	set var_array(30,redirect) 	[list ">" "stdout" "string" "1" "1" "" "Redirects the output to a file" ]

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

	if { "$redirect" != "stdout" } {
		set fileId [open ${redirect} w 0640]
		puts $fileId "# Automatically generated by $argv0 on [exec date]"
		puts $fileId ""
	} else {
		set fileId stdout
	}

	puts $fileId "set my_shift_inv_clk {"
	foreach iii $last_clk_inverters {
		regsub -all {/} $iii {.} jjj
		puts $fileId "	${jjj}.Z=\[P\]"
	}
	puts $fileId "}"

	puts $fileId ""
	puts $fileId "proc disconnect_inverter_ports { } {"
	foreach iii $last_clk_inverters {
		regsub -all {/} $iii {.} jjj
		puts $fileId "	disconnect_port -port ${jjj}.A"
	}
	puts $fileId "}"

	close $fileId
}
# END
################################################################################


################################################################################
# BEGIN write
# procedure used to write in a more structural way relevant information about
# design
proc ::octopusRC::write args {

	global previous-state
	global DESIGN

	set var_array(10,current-state)		[list "--current-state" "<none>" "string" "1" "1" "" "String specifying the design state. Can be anything but recommended values are rtl, syn, scn. It is used in file names." ]
	set var_array(20,netlist-path)		[list "--netlist-path" "<none>" "string" "1" "1" "" "Path were the netlist is written to." ]
	set var_array(30,no-netlist)		[list "--no-netlist" "false" "boolean" "" "" "" "Prevents writing the design netlist" ]
	set var_array(40,no-lec)		[list "--no-lec" "false" "boolean" "" "" "" "Prevents writing out the lec do files" ]
	set var_array(50,no-database)		[list "--no-database" "false" "boolean" "" "" "" "Prevents writing the design database" ]
	extract_check_options_data
	::octopus::abort_on error --return --display-help

	if { ! [info exists previous-state] } {
		set previous-state "rtl"
		set gdc ""
	} else {
		set gdc "-golden_design ${netlist-path}/${DESIGN}_netlist_${previous-state}.v"
	}

	if { "${no-netlist}" == "false" } {
		set ntlst ${netlist-path}/${DESIGN}_netlist_${current-state}.v
		::octopus::display_message debug "<5> Writing netlist: $ntlst "
		write_hdl >  $ntlst
	}
	if { "${no-lec}" == "false" && "$::octopusRC::run_speed" != "fast"} {
		set lecdo "generated/${DESIGN}_do_lec_${previous-state}2${current-state}.cmd"
		::octopus::display_message debug "<5> Writing lec do file : $lecdo "
		uplevel #0 { eval 
			write_do_lec \
				-hier \
				$gdc \
				-revised_design ${ntlst} \
				> $lecdo
			}
	}
	if { "${no-database}" == "false" && "$::octopusRC::run_speed" != "fast"} {
		shell mkdir -p db
		uplevel #0 { eval write_db ${DESIGN} -all_root_attributes -to_file db/${DESIGN}_${current-state}.db}
	}

	set previous-state ${current-state}
}
# END
################################################################################


################################################################################
# BEGIN elaborate
# procedure used to write in a more structural way relevant information about
# design
proc ::octopusRC::elaborate args {


	set var_array(10,DESIGN)		[list "--design" "<none>" "string" "1" "1" "" "Design for which elaboration will take place" ]
	set var_array(20,_REPORTS_PATH)		[list "--reports-path" "./rpt/" "string" "1" "1" "" "Where the reports will be generated" ]
	extract_check_options_data
	::octopus::abort_on error --return --display-help

	eval uplevel #0 {elaborate ${DESIGN}}

	puts "Runtime & Memory after 'read_hdl'"
	timestat Elaboration

	if { "$::octopusRC::run_speed" != "fast"} {
	set date [exec date +%s]
	check_design -all ${DESIGN} > ${_REPORTS_PATH}/${DESIGN}_check_design_${date}.rpt
	report ple > ${_REPORTS_PATH}/${DESIGN}_report_ple.rpt
	}
}
# END
################################################################################


################################################################################
# BEGIN read_cpf
# procedure used to write in a more structural way relevant information about
# design
proc ::octopusRC::read_cpf args {

	set var_array(10,cpf)		[list "--cpf" "<none>" "string" "1" "1" "" "CPF file" ]
	set var_array(20,DESIGN)	[list "--design" "<none>" "string" "1" "1" "" "Design name" ]
	set var_array(30,_REPORTS_PATH)	[list "--reports-path" "./rpt/" "string" "1" "1" "" "Where the reports will be generated" ]
	extract_check_options_data
	set  help_head {
		::octopus::display_message none "Reads the CPF file and does standard checks"
	}
	::octopus::abort_on error --return --display-help

	eval uplevel #0 {read_cpf $cpf}

	if { "$::octopusRC::run_speed" != "fast"} {
		set date [exec date +%s]
		check_library 		> ${_REPORTS_PATH}/${DESIGN}_check_library_${date}.rpt
		check_cpf -detail 	> ${_REPORTS_PATH}/${DESIGN}_check_cpf_${date}.rpt
		check_design -all 	> ${_REPORTS_PATH}/${DESIGN}_check_design_${date}.chk
	}
}
# END
################################################################################


################################################################################
# BEGIN synthesize
# procedure used to write in a more structural way relevant information about
# design
proc ::octopusRC::synthesize args {

	set var_array(10,type)		[list "--type" "<none>" "string" "1" "1" "to_generic to_mapped to_mapped_incremental" "Specify to synthesis type" ]
	set var_array(20,netlist-path)	[list "--netlist-path" "<none>" "string" "1" "1" "" "Path were the netlist is written to." ]
	set var_array(30,DESIGN)	[list "--design" "<none>" "string" "1" "1" "" "Design name" ]
	set var_array(40,_REPORTS_PATH)	[list "--reports-path" "./rpt/" "string" "1" "1" "" "Where the reports will be generated" ]
	extract_check_options_data
	set  help_head {
		::octopus::display_message none "Synthesize the design and writes out useful files: netlist, lec do, "
	}
	::octopus::abort_on error --return --display-help

	# Specify the effort required for Generic Synthesis. It is recommended to
	# specify medium for Generic and non incremental synthesis for the first run
	if { 	"[get_attribute octopusRC_design_maturity_level]" != "pyrate" && \
		"[get_attribute octopusRC_design_maturity_level]" != "bronze"} {
		set effort_generic 	medium
		set effort_mapped 	medium
		set effort_incremental	medium
	} else {
		set effort_generic 	high
		set effort_mapped 	high
		set effort_incremental	high
	}

	switch -- $type {
		to_generic {
			eval uplevel #0 {synthesize -to_generic -eff $effort_generic}
			puts "Runtime & Memory after synthesize to generic"
			timestat GENERIC
			::octopusRC::write --current-state gen --netlist-path ${netlist-path}
		}
		to_mapped {
			eval uplevel #0 {synthesize -to_mapped -eff $effort_mapped -no_incr -auto_identify_shift_register}
			puts "Runtime & Memory after synthesize to mapped"
			timestat MAPPED
			::octopusRC::write --current-state mapped --netlist-path ${netlist-path}
			set date [exec date +%s]
			check_design -all > $_REPORTS_PATH/${DESIGN}_check_design_${date}.chk
		}
		to_mapped_inc {
			eval uplevel #0 {synthesize -to_mapped -eff $effort_incremental -incr}
			report summary
			puts "Runtime & Memory after incremental synthesis"
			timestat INCREMENTAL
			::octopusRC::write --current-state inc_scn --netlist-path ${netlist-path}
		}
	}
}
# END
################################################################################


################################################################################
# BEGIN set_case_analysis
# procedure used to set_case_analysis based on the test data files of the TCB's'
proc ::octopusRC::set_case_analysis args {

	::octopus::display_message warning "Entering poorly tested procedure!!!"

	set var_array(10,tcb-td-file)		[list "--tcb-td-file" "<none>" "string" "1" "infinity" "" "TCB test data file(s)" ]
	set var_array(20,mode)			[list "--mode" "<none>" "string" "1" "1" "" "TCB mode for which constant values are extracted" ]
	set var_array(30,skip-signal)		[list "--skip-signal" "" "string" "1" "infinity" "" "Skip the TCB signal(s)" ]
	set var_array(40,constraint-file)	[list "--constraint-file" "<none>" "string" "1" "1" "" "The name of the file where the constraints are written into" ]
	set var_array(50,append)		[list "--append" "false" "boolean" "" "" "" "Appends into <constraint-file> instead of truncating it" ]
	extract_check_options_data
	set  help_head {
		::octopus::display_message none "Extracts the TCB values in a specific mode and writes out set_case_analysis statements"
	}
	::octopus::abort_on error --return --display-help

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
	puts $fileIDsdc "# File created by ::octopusRC::set_case_analysis procedure"
	set date_time [exec date]
	puts $fileIDsdc "# on :: $date_time"

	# parse one file at a time
	foreach crt_file ${tcb-td-file} {
		puts $fileIDsdc ""
		set ports ""
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
							lappend ports [list $port $value_int]
							}
						}
					# found our mode so no need to continue parsing the file
					break
				}
			}
			# Create set_case_analysis statements
			puts $fileIDsdc "################################################################################"
			puts $fileIDsdc "# 	TCB test data file: $crt_file"
			puts $fileIDsdc "# 	TCB mode: $mode"
			puts $fileIDsdc ""
			foreach cpv $ports {
				set crt_port 	[lindex $cpv 0]
				set crt_value 	[lindex $cpv 1]
				if {! [string match "* $crt_port *" " ${skip-signal} "] } {
					set instance_path [get_attribute instances [find /des* -subdes $cell ]]
					if { [llength $instance_path] <=1 } {
						set full_path_fanin [vname [fanin -max_pin_depth 1 ${instance_path}/${crt_port}]]
						if { $full_path_fanin ==  1 } {
							::octopus::display_message error "Could not find ${instance_path}/${crt_port} in $DESIGN"
						} else {
							puts $fileIDsdc "#Derived from: ${crt_port}"
							puts $fileIDsdc "set_case_analysis $crt_value $full_path_fanin"
						}
					} else {
						::octopus::display_message error "More than one TCB instantiation for $cell module has been found. Don't know what to td :-("
					}
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

	set var_array(10,file)		[list "--file" "<none>" "string" "1" "infinity" "" "File(s) containing the list with all RTL to be read " ]
	set var_array(20,type)		[list "--type" "<none>" "string" "1" "1" "text utel rc" "type of file to read in" ]
	extract_check_options_data
	set  help_head {
		::octopus::display_message none "Reads in RTL files based on certain types of file lists"
		::octopus::display_message none "currently only rc and utel file list are supported"
	}

	::octopus::abort_on error --return --display-help

	set file_set_total [::octopus::parse_file_set --type utel --file $file]

	foreach x $file_set_total {
		foreach { f t l o } $x {
			case $t in {
			"verilog" {
				eval uplevel #0 {read_hdl $f -library $l}
				}
			"vhdl" {
				eval uplevel #0 {read_hdl -vhdl $f -library $l}
				}
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

	global DESIGN

	set  help_head {
		::octopus::display_message none "Deletes the unloaded and undriven. Depending on the design maturity this command is activated or not"
	}

	if { 	"[get_attribute octopusRC_design_maturity_level]" != "pyrite" && \
		"[get_attribute octopusRC_design_maturity_level]" != "bronze"} {
		uplevel #0 {delete_unloaded_undriven -all -force_bit_blast ${DESIGN}}
	} else {
		display_message info "Skiping delete_unloaded_undriven due to the maturity of the design: [get_attribute octopusRC_design_maturity_level]"
	}

	::octopus::append_cascading_variables
}
# END
################################################################################
