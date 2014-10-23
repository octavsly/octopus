############################################################
# libterm.tcl                                              #
############################################################
# VT100 Terminal Library for TCL.                          #
############################################################
#                                                          #
# 0.9.0 - 'mv' supports 'home' argument.                   #
#       - 'mv' supports single directions chars,           #
#         as movement by 1 char.                           #
#       - Added 'erase'.                                   #
#       - Added 'reset'.                                   #
#                                                          #
# 0.8.0 - Implemented tputs, rtputs, mv and curpos.        #
#                                                          #
############################################################
# This application is free software. It can be distributed #
# and modified in pursuance with GNU General Public        #
# Licence publicated by Free Software Fundation in version #
# 2 with later changes.                                    #
############################################################

package require Tcl 8.3

namespace eval ::libterm {
    package provide libterm 0.9.0
    namespace export tputs rtputs curpos mv erase reset scroll
}

fconfigure stdout -buffering none

proc ::libterm::ansi_replace {string} {
    set idx [string first % "$string"]
    set startidx 0
    set sw 0
    while {$idx > -1} {
        if {"[string index {$string} [expr {$idx + 1}]]" == "%"} {
            append string2 "[string range $string $startidx [expr {$idx - 1}]]%"
            incr idx
        } else {
            append string2 "[string range $string $startidx [expr {$idx - 1}]]\033\[\0"
            while {[string index "$string" $idx] == "%"} {
                incr idx
                set char [string index "$string" $idx]
                if {"$char" == "#"} {
                    incr idx
                    set char [string index "$string" $idx]
                    set sw 1
                }
                append string2 "\;"
                if {$sw} {
                    append string2 "[string map {b 44 r 41 g 42 y 43 m 45 w 47 k 40 c 46 n 0 \
                        K 100 R 101 G 102 Y 103 B 104 M 105 C 106 W 107 d 1 u 4 l 5 v 7} $char]"
                    set sw 0
                } else {
                    append string2 "[string map {b 34 r 31 g 32 y 33 m 35 w 37 k 30 c 36 n 0 \
                        K 90 R 91 G 92 Y 93 B 94 M 95 C 96 W 97 d 1 u 4 l 5 v 7} $char]"
                }
                incr idx
            }
            append string2 m
            set startidx $idx
            set idx [string first % "$string" $startidx]
        }
    }
    append string2 "[string range $string $startidx end]"
    return "$string2"
}

proc ::libterm::ansi_remove {string} {
    set idx [string first % "$string"]
    set startidx 0
    set sw 0
    while {$idx > -1} {
        if {"[string index "$string" [expr {$idx + 1}]]" == "%"} {
            append string2 "[string range $string $startidx [expr {$idx - 1}]]%"
            incr idx
        } else {
            append string2 "[string range $string $startidx [expr {$idx - 1}]]\033\[\0"
            while {[string index "$string" $idx] == "%"} {
                incr idx
                set char [string index "$string" $idx]
                if {"$char" == "#"} {
                    incr idx
                    set char [string index "$string" $idx]
                    set sw 1
                }
                append string2 "\;"
                if {$sw} {
                    append string2 "[string map {b {} r {} g {} y {} m {} w {} k {} c {} n {} \
                        K {} R {} G {} Y {} B {} M {} C {} W {} d {} u {} l {}} $char]"
                    set sw 0
                } else {
                    append string2 "[string map {b {} r {} g {} y {} m {} w {} k {} c {} n {} \
                        K {} R {} G {} Y {} B {} M {} C {} W {} d {} u {} l {}} $char]"
                }
                incr idx
            }
            append string2 m
            set startidx $idx
            set idx [string first % "$string" $startidx]
        }
    }
    append string2 "[string range $string $startidx end]"
    return "$string2"
}

proc ::libterm::rtputs {args} {
    global ansi
    if { ! [info exists ansi] } {
        set ansi 1
    }
    switch -- [llength $args] {
        1 {
            set arg [lindex $args end]
        }
        2 {
            if {"[lindex $args 0]" == "-nonewline"} {
                set nnl 1
            } elseif {"[lindex $args 0]" == "-nocolors"} {
                set ansi 0
            } else {
                set channelID [lindex $args 0]
            }
            set arg [lindex $args end]
        }
        3 {
            if {"[lindex $args 0]" == "-nonewline"} {
                set nnl 1
                set channelID [lindex $args 2]
            } elseif {"[lindex $args 0]" == "-nocolors"} {
                set ansi 0
                set channelID [lindex $args 2]
            } else {
                error {wrong # args: rtputs ?-nonewline? ?-nocolors? ?channelID? string}
            }
            set arg [lindex $args end]
        }
        4 {
            if {"[lindex $args 0]" == "-nonewline" && "[lindex $args 1]" == "-nocolors"} {
                set nnl 1
                set ansi 0
                set channelID [lindex $args 2]
            } else {
                error {wrong # args: rtputs ?-nonewline? ?-nocolors? ?channelID? string}
            }
        }
        default {
            error {wrong # args: rtputs ?-nonewline? ?-nocolors? ?channelID? string}
        }
    }
    append arg "%n"
    if {$ansi} {
        set output "[string map {%% % %b \033\[0\;34m %r \033\[0\;31m \
                %g \033\[0\;32m %y \033\[0\;33m %m \033\[0\;35m %w \033\[0\;37m %k \033\[0\;30m \
                %c \033\[0\;36m %n \033\[0\;0\;m %K \033\[0\;90m %R \033\[0\;91m %G \033\[0\;92m \
                %Y \033\[0\;93m %B \033\[0\;94m %M \033\[0\;95m %C \033\[0\;96m %W \033\[0\;97m \
                %#r \033\[0\;40m %#k \033\[0\;41m %#g \033\[0\;42m %#y \033\[0\;43m %#b \033\[0\;44m \
                %#m \033\[0\;45m %#c \033\[0\;46m %#K \033\[0\;100m %#R \033\[0\;101m \
                %#G \033\[0\;102m %#Y \033\[0\;103m %#B \033\[0\;104m %#M \033\[0\;105m %#C \033\[0\;106 \
                %#W \033\[0\;107m %#w \033\[0\;47m %d \033\[0\;1m %u \033\[0\;4m %l \033\[0\;5m %v \033\[0\;7m} $arg]"
    } else {
        set output [string map {%% % %b "" %r "" \
                %g "" %y "" %m "" %w "" %k "" \
                %c "" %n "" %K "" %R "" %G "" \
                %Y "" %B "" %M "" %C "" %W "" \
                %#r "" %#k "" %#g "" %#y "" %#b "" \
                %#m "" %#c "" %#K "" %#R "" \
                %#G "" %#Y "" %#B "" %#M "" %#C "" \
                %#W "" %#w "" %d "" %u "" %l "" %v ""} $arg]
	set output_log_file $output
    }
    if {[info exists nnl]} {
        if {[info exists channelID]} {
             puts -nonewline $channelID "$output"
        } else {
            puts -nonewline "$output"
        }
    } else {
        if {[info exists channelID]} {
            puts $channelID "$output"
        } else {
            puts "$output"
        }
    }
}

proc ::libterm::tputs {args} {
    set ansi 1
    switch -- [llength $args] {
        1 {
            set arg [lindex $args end]
        }
        2 {
            if {"[lindex $args 0]" == "-nonewline"} {
                set nnl 1
            } elseif {"[lindex $args 0]" == "-nocolors"} {
                set ansi 0
            } else {
                set channelID [lindex $args 0]
            }
            set arg [lindex $args end]
        }
        3 {
            if {"[lindex $args 0]" == "-nonewline"} {
                set nnl 1
                set channelID [lindex $args 2]
            } elseif {"[lindex $args 0]" == "-nocolors"} {
                set ansi 0
                set channelID [lindex $args 2]
            } else {
                error {wrong # args: tputs ?-nonewline? ?-nocolors? ?channelID? string}
            }
            set arg [lindex $args end]
        }
        4 {
            if {"[lindex $args 0]" == "-nonewline" && "[lindex $args 1]" == "-nocolors"} {
                set nnl 1
                set ansi 0
                set channelID [lindex $args 2]
            } else {
                error {wrong # args: tputs ?-nonewline? ?-nocolors? ?channelID? string}
            }
        }
        default {
            error {wrong # args: tputs ?-nonewline? ?-nocolors? ?channelID? string}
        }
    }
    append arg "%n"
    if {$ansi} {
        set arg "[::libterm::ansi_replace $arg]"
    } else {
        set arg "[::libterm::ansi_remove $arg]"
    }
    if {[info exists nnl]} {
        if {[info exists channelID]} {
            puts -nonewline $channelID "$arg"
        } else {
            puts -nonewline "$arg"
        }
    } else {
        if {[info exists channelID]} {
            puts $channelID "$arg"
        } else {
            puts "$arg"
        }
    }
}

proc ::libterm::mv {args} {
    set args [string tolower $args]
    if {"$args" != ""} {
        if {[lsearch "u d l r" [string index [lindex $args 0] 0]] > -1} {
            foreach arg $args {
                switch -- [string index $arg 0] {
                    u {
                        if {"[string range $arg 1 end]" != ""} {
                            if {[string is digit [string range $arg 1 end]]} {
                                puts -nonewline "\033\[[string range $arg 1 end]A"
                            }
                        } else {
                            puts -nonewline "\033\[A"
                        }
                    }
                    d {
                        if {"[string range $arg 1 end]" != ""} {
                            if {[string is digit [string range $arg 1 end]]} {
                                puts -nonewline "\033\[[string range $arg 1 end]B"
                            }
                        } else {
                            puts -nonewline "\033\[B"
                        }
                    }
                    l {
                        if {"[string range $arg 1 end]" != ""} {
                            if {[string is digit [string range $arg 1 end]]} {
                                puts -nonewline "\033\[[string range $arg 1 end]D"
                            }
                        } else {
                            puts -nonewline "\033\[D"
                        }
                    }
                    r {
                        if {"[string range $arg 1 end]" != ""} {
                            if {[string is digit [string range $arg 1 end]]} {
                                puts -nonewline "\033\[[string range $arg 1 end]C"
                            }
                        } else {
                            puts -nonewline "\033\[C"
                        }
                    }
                    default {
                        error {wrong # args: mv lines ?lines ...?|position}
                    }
                }
            }
        } elseif {"[lindex $args 0]" == "home"} {
            puts -nonewline "\033\[H"
        } else {
            set arg [lindex $args 0]
            if {[string match *,* "$arg"]} {
                if {[string is digit [lindex [split $arg ,] 0]] && [string is digit [lindex [split $arg ,] 1]]} {
                    puts -nonewline "\033\[[string map {, \;} $arg]H"
                } else {
                    error {wrong # args: mv lines ?lines ...?|position}
                }
            } else {
                if {[string is digit $arg]} {
                    puts -nonewline "\033\[$arg\;0H"
                } else {
                    error {wrong # args: mv lines ?lines ...?|position}
                }
            }
        }
    }
}

proc ::libterm::curpos {saveOrLoad} {
    if {"[string tolower $saveOrLoad]" == "save"} {
        puts -nonewline "\033\[s"
    } elseif {"[string tolower $saveOrLoad]" == "load"} {
        puts -nonewline "\033\[u"
    } else {
        error {wrong # args: curpos save|load}
    }
}

proc ::libterm::erase {lineOrScreen {type {right}}} {
    switch -- [string tolower $lineOrScreen] {
        line {
            switch -- [string tolower $type] {
                right {
                    puts -nonewline "\033\[0K"
                }
                left {
                    puts -nonewline "\033\[1K"
                }
                both {
                    puts -nonewline "\033\[2K"
                }
            }
        }
        screen {
            switch -- [string tolower $type] {
                right {
                    puts -nonewline "\033\[0J"
                }
                left {
                    puts -nonewline "\033\[1J"
                }
                both {
                    puts -nonewline "\033\[2J"
                }
            }
        }
        default {
            error {wrong # args: erase line|screen type}
        }
    }
}

proc ::libterm::reset {} {
    puts -nonewline "\033\c"
}

proc ::libterm::scroll {regionOrMode} {
    set regionOrMode [split $regionOrMode ,]
    if {[llength $regionOrMode] == 2} {
        if {[string is digit [lindex $regionOrMode 0]] && [string is digit [lindex $regionOrMode 1]]} {
            puts -nonewline "\033\[[lindex $regionOrMode 0]\;[lindex $regionOrMode 1]r"
        }
    } elseif {"full" == "$regionOrMode"} {
        puts -nonewline "\033\[?6h"
    } elseif {"region" == "$regionOrMode"} {
        puts -nonewline "\033\[?6l"
    } else {
        error {wrong # args: scroll mode}
    }
}
