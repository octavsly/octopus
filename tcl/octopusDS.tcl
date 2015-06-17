#
#    octopusDS: DesignSync package of useful procedures
#    Copyright (C) 2012-2013 Octavian Petre <octavian.petre@nxp.com>.
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

package provide octopusDS 0.1

package require Tcl 8.3
package require libterm 0.9.0
package require octopus 0.1


namespace eval ::octopusDS {
	namespace import ::libterm::*
	namespace import ::octopus::*

	#namespace export \

	variable authors "Octavian Petre"
	variable authors_email "octavsly@gmail.com"
	variable url_project {none}

}
