#!/bin/bash this script is to be sourced, not run

# tbl.sh - minimalistic bash library for data table operations.
# Copyright (C) 2025 step, https://github.com/step-
# Licensed under the GNU General Public License Version 2

# Project home page: https://github.com/step-/tbl.sh
# Version 1.0.0

# Refer to the tbl_demo() function for a full example.

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# Design
# ======
# - Multiple data tables can exist as separate files but only one can be
#   loaded into memory at a time, simplifying global state management.
# - Immutable row and column numbers are the positive indices of the
#   rows/columns of the table; these never change after loading.
# - The active range is the subset of immutable row/column numbers identifying
#   the visible rows/columns at any one point.
# - Table functions accept immutable row/column numbers as arguments, and
#   operate on the active range internally.
# - The active range is initialized to include all input rows and columns
#   upon loading the table via tbl_load().
# - Functions like tbl_filter() and tbl_slice() for rows, and tbl_select()
#   for columns modify the active range to show or hide elements by adding
#   or removing their public numbers from the active range.
# - Function tbl_print() outputs the table restricted by the active range.
# - The current active range can be saved and restored, allowing for reversible
#   operations and state management.

tbl_fetch_col_vars() { # $1-col_var_path $2-col_nums_path $3-col_hdrs_path
	# Call an application-defined function to generate column variable names,
	# process its output, and write the results to files:
	#   - column variables to $1,
	#   - column numbers to $2,
	#   - column header labels to $3.
	#
	# Returns 1 on error.

	local col_vars="${1:?}"
	local col_nums="${2:?}"
	local col_hdrs="${3:?}"
	local fdi fdh fdn fdv v varname
	local -i n=0

	if [[ $(type -t app_tbl_col_vars_generator) != function ]]; then
		cat << EOF >&2
Error: missing function 'tbl_app_col_vars_generator'.

This function must output a newline-separated list of column variable names.
Each variable name must start with an underscore ('_') and may include only
ASCII alphanumeric characters and underscores.

Columns are header-less. To associate labels, preset variables named 'i18n_col_'
followed by the column name. Assign each label text starting with a namespace of
your choice followed by a colon. The namespace and colon will be removed from
the final label. For example: i18n_col_JOB='ns:Role' for a JOB column variable.
Labels may be used programmatically to display headers before calling tbl_print.

Refer to the '$BASH_SOURCE' file for more details.
EOF
		return 1
	fi

	exec {fdh}> "$col_hdrs" {fdn}> "$col_nums" {fdv}> "$col_vars" ||
		return 1

	# Read the application-defined col_vars list.
	# The app*generator should signal its errors to $$,
	# and $$ should set up traps to handle such errors.
	# We do not want to do it here.
	exec {fdi}< <(app_tbl_col_vars_generator)

	while read -u $fdi v; do
		echo $((++n)) >&$fdn
		printf '%s\n' $v >&$fdv
		typeset -n varname=i18n_col_$v
		printf "%s\n" "${varname#*:}" >&$fdh
		typeset +n varname
		unset varname
	done
	exec {fdi}<&- {fdh}>&- {fdn}>&- {fdv}>&-
}

tbl_declare_globals() { # $1-col_vars_path $2-col_nums_path
	# tbl_fetch_col_vars() is called before this function to create $1 and $2.
	#
	# Declare global variables representing the table:
	# - Integer constants for immutable column numbers named after the table
	#   variable names listed in $1, e.g. _A, _B, _C if these are in $1.
	# - Indexed arrays 'col_'<table_variable> for all table variables.
	# - The indexed array `colV[]` holding the column variable names.

	local vf=${1:?} nf=${2:?}
	local v fdv n fdn
	local -a arow=() acol=()
	local -i i=0

	typeset -ga colV=()

	exec {fdv}< "$vf" {fdn}< "$nf"
	while read -u $fdv v && read -u $fdn n; do
		let ++i
		acol+=($i)
		typeset -gi "$v=$n"
		typeset -ga "col$v=($n)"    # col_$v[0] column number.
		colV[i]="$v"                # colV[i]   variable names.
	done
	exec {fdv}<&- {fdn}<&-

	colV[0]="${arow[*]}:${acol[*]}"     # colV[0] active range
}

tbl_load() { # $1_input_field_delimiter
	# Assumes tbl_declare_globals() has been called before this function.
	#
	# Load a data frame from stdin into the declared table globals, and
	# initialize its immutable row and column numbers and the active range.
	#
	# Returns 1 if corrupted globals are detected.
	#
	# The table structure (rows and columns) is immutable. However,
	# specific rows can be hidden with filters (tbl_filter), and specific
	# columns can be selected (tbl_select). The table presentation
	# (tbl_print) reflects these filters and selections.

	local delim=${1:?}
	local -i r=0 c
	local active
	local -a arow acol
	local row col

	[ -n "${colV[0]}" ] || return 1
	active=${colV[0]}
	acol=(${active#*:})

	while read row; do
		let ++r
		IFS='|' read -r -a a <<< "$row"
		# Work-around for bash splitting a trailing "||"
		# as one item but "||x" as two items.
		[[ $row == *'||' ]] && a+=('')

		for ((c = 1; c <= ${#acol[*]}; c++)); do
			[ -n "${colV[c]}" ] || return 1
			typeset -n col=col${colV[c]}
			[ -n "${col[0]}" ] || return 1
			[ "${col[0]}" -eq $c ] || return 1
			col[r]=${a[c - 1]}
			typeset +n col
			unset col
		done
		arow+=($r)
	done
	colV[0]="${arow[*]}:${acol[*]}"
}

tbl_print() { # $1-output_field_delimiter [$2-NA_value] [$3-row_number_flag]
	# Print the active range table to stdout using $1 as the column separator.
	# If $2 (NA) is not empty, its value is printed to fill empty cells.
	# If $3 is not empty, a temporary column is printed before column 1 to
	# display the immutable row number.
	#
	# Returns 1 if corrupted globals are detected.

	local delim=${1:?}
	local na=$2
	local rnum=$3
	local r c ifs="$IFS"
	local IFS
	local active arow acol
	local -a row
	local col

	[ -n "${colV[0]}" ] || return 1
	active=${colV[0]}
	arow=${active%:*} acol=${active#*:}
	[ -n "$arow" ] && [ -n "$acol" ] || return 0

	for r in $arow; do                       # active rows
		row=()
		for c in $acol; do               # active columns
			[ -n "${colV[$c]}" ] || return 1
			typeset -n col=col${colV[$c]}
			[ -n "${col[0]}" ] || return 1
			[ "${col[0]}" -eq $c ] || return 1
			if [ -z "$na" ]; then
				row[$c]=${col[$r]}
			elif [ -z "${col[$r]}" ]; then
				row[$c]=$na
			else
				row[$c]=${col[$r]}
			fi
			typeset +n col
			unset col
		done
		[ "$rnum" ] && rnum=$r$delim
		IFS="$delim"
		printf '%s%s\n' "$rnum" "${row[*]}"
		IFS="$ifs"
	done
}

tbl_get_active_range() { # $1-varname
	# Assign ${$1} the active range, which is the set of.
	# row/column numbers function tbl_print() will show.
	# Returns 1 if corrupted globals are detected.

	local -n varname=${1:?}
	[ -n "${colV[0]}" ] && varname="${colV[0]}" || return 1
}

tbl_set_active_range() { # $1-new_range_spec (arows:acols)
	# Returns 1 if corrupted globals are detected.

	[ -n "${colV[0]}" ] && colV[0]="$1" || return 1
}

tbl_get_inactive_range() { # $1-varname
	# Assign ${$1} the inactive range, which is the set of
	# row/column numbers function tbl_print() will hide.
	# Returns 1 if corrupted globals are detected.

	local -n varname=${1:?}
	local -a irow icol
	local -i r c row col
	local active arow acol
	local var

	[ -n "${colV[0]}" ] || return 1

	active=${colV[0]}
	arow=${active%:*} acol=${active#*:}

	ncol=${#colV[*]}

	typeset -n var=col${colV[1]}
	typeset nrow=${#var[*]}

	for ((r = 1; r < nrow; r++)); do
		[[ " $arow " == *" $r "* ]] || row[r]=$r
	done
	for ((c = 1; c < ncol; c++)); do
		[[ " $acol " == *" $c "* ]] || col[c]=$c
	done
	varname="${row[*]}:${col[*]}"
}

tbl_filter() { # $1-expression [$2-max_subst]
	# Restrict the active row range to rows matching the $1 bash conditional
	# expression. The $2 argument sets the maximum number of substitutions
	# allowed (see SUBSTITUTIONS), defaulting to 100.
	#
	# Returns 1 if corrupted globals are detected.
	# Returns 2 if the substitution limit is exceeded.
	#
	# CAVEAT: The condition is not sanitized before evaluation.
	# The caller must sanitize input to prevent `eval` exploits.
	#
	# The condition is wrapped with '[[' and ']]' and evaluated using bash
	# `eval`. An example extracted from tbl_demo():
	#     "-n ${_a_[9]}" || "${_a_[4]}" == "ddd"
	# where the special array `_a_[]` holds the current row.
	#
	# SUBSTITUTIONS: Since global constants are predefined for immutable
	# column numbers, _D and _J can replace 4 and 9 in the example, thus:
	#     "-n ${_a_[_J]}" || "${_a_[_D]}" == "ddd"
	# This expression can be further simplified to its final form:
	#     -n _J || _D == "ddd"
	# The last form is transformed into the first one before evaluation.
	#
	# The modified active row range remains until reset by restoring from
	# a backup with tbl_get_active_range() or by calling tbl_load().

	local ex=${1:?}
	local -i max_subst=${2:-100}
	local -i ctr=0
	local r col
	local active arow acol
	local -a _a_ keep=()

	[ -n "${colV[0]}" ] || return 1
	active=${colV[0]}
	arow=${active%:*} acol=${active#*:}
	[ -n "$arow" ] && [ -n "$acol" ] || return 0

	# sed-based substitution:
	# [[ $ex =~ (^|[ \\t])([-+]?)(_[A-Za-z_]+) ]] &&
	# 	ex="$(sed -E 's/(^|[ \t])([-+]?)(_[A-Za-z_]+)/\1\2"${_a_[\3]}"/g'<<<" $ex")"
	ctr=0
	while ((ctr <= max_subst)) &&
		[[ $ex =~ ^(.*)(^|[ \\t])([-+]?)(_[A-Za-z_]+)(.*)$ ]]; do
		((++ctr))
		ex="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}\${_a_[${BASH_REMATCH[4]}]}${BASH_REMATCH[5]}"
	done
	((ctr < max_subst)) || return 2
	# : "${colV[*]}"

	for r in $arow; do                       # active rows
		_a_=()
		for c in $acol; do               # active columns
			[ -n "col${colV[$c]}" ] || return 1
			typeset -n col=col${colV[$c]}
			[ -n "${col[0]}" ] || return 1
			[ "${col[0]}" -eq $c ] || return 1
			_a_[$c]="${col[$r]}"
			typeset +n col
			unset col
		done
		eval [[ $ex ]] && keep+=($r)
	done
	colV[0]="${keep[*]}:$acol"
}

tbl_slice() { # $1-row_list
	# Select rows from the active row range based on the given list.
	#
	# The $1 argument is a space-separated list of signed integers,
	# predefined global constants for immutable row numbers, or the
	# wildcards '*' and '-*' representing all rows.
	# List elements starting with '-' remove rows from the active range,
	# while other elements add rows to the range.
	#
	# Examples:
	#   '3 -7'  adds row 3 and removes row 7.
	#   '-* 5'  keeps only row 5.
	#
	# Returns 1 if corrupted globals are detected.
	#
	# The modified active row range remains until reset by restoring
	# from a backup with tbl_get_active_range() or by calling tbl_load().

	local rlst=${1:?}
	local r col
	local active arow acol
	local -ai keep

	[ -n "${colV[0]}" ] || return 1
	active=${colV[0]}
	arow=${active%:*}
	typeset -r acol=${active#*:}
	[ -n "$arow" ] && [ -n "$acol" ] || return 0

	for r in $arow; do keep[r]=r; done
	for r in $rlst; do
		if [[ $r == '-*' ]]; then
			keep=()
		elif [[ $r == '*' ]]; then
			keep=()
			for r in $arow; do keep[r]=r; done
		elif ((r < 0)); then
			unset keep[$((-r))]
		elif ((r > 0)); then
			keep[r]=r
		fi
	done
	colV[0]="${keep[*]}:$acol"
}

tbl_select() { # $1-column_list [$2-max_subst]
	# Add or remove immutable column numbers from the active column range.
	#
	# The $1 argument is a space-separated list of signed integers,
	# predefined global constants for immutable column numbers, or the
	# wildcards '*' and '-*' representing all columns.
	# List elements starting with '-' remove columns from the active range,
	# while other elements add columns to the range.
	#
	# Examples:
	#   '4 -5'  adds column 4 and removes column 5.
	#   '-* 2'  keeps only column 2.
	#
	# The $2 argument sets the maximum number of substitutions allowed
	# (see SUBSTITUTIONS), defaulting to 100.
	#
	# SUBSTITUTIONS: Column constants are replaced by their numeric values.
	# For example, '_D -_E' or '-* _B'  (refer to tbl_filter()).
	#
	# Returns 1 if corrupted globals are detected.
	# Returns 2 if the substitution limit is exceeded.
	#
	# The modified active column range remains until reset by restoring
	# from a backup with tbl_get_active_range() or by calling tbl_load().

	local clst="${1:?}"
	local -i max_subst=${2:-100}
	local -i ctr=0
	local c
	local active arow acol
	local -ai keep

	[ -n "${colV[0]}" ] || return 1
	active=${colV[0]}
	arow=${active%:*}
	typeset -r acol=${active#*:}
	[ -n "$arow" ] && [ -n "$acol" ] || return 0

	# sed-based substitution:
	# [[ $clst =~ (^|[ \\t])([-+]?)_[A-Z_]+) ]] &&
	# 	clst="$(sed -E 's/(^|[ \t])([-+]?)(_[A-Za-z_]+)/\1\2"$\3"/g'<<<" $clst")"
	ctr=0
	while ((ctr <= max_subst)) &&
		[[ $clst =~ ^(.*)(^|[ \\t])([-+]?)(_[A-Za-z_]+)(.*)$ ]]; do
		((++ctr))
		clst="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}\$${BASH_REMATCH[4]}${BASH_REMATCH[5]}"
	done
	((ctr < max_subst)) || return 2
	# : "${colV[*]}"

	clst="${clst@P}"

	for c in $acol; do keep[c]=c; done
	for c in $clst; do
		if [[ $c == '-*' ]]; then
			keep=()
		elif [[ $c == '*' ]]; then
			keep=()
			for c in $acol; do keep[c]=c; done
		elif ((c < 0)); then
			unset keep[$((-c))]
		elif ((c > 0)); then
			keep[c]=c
		fi
	done
	colV[0]="$arow:${keep[*]}"
}

if [ "$TBL_DEMO" ]; then
tbl_demo() {
	local initial active inactive v c

	#######################
	#  APPLICATION SETUP  #
	#######################

	# This is a sample of the application-defined function that
	# generates the table column variable names.

	app_tbl_col_vars_generator() {
		printf '%s\n' \
		_A \
		_B \
		_C \
		_D \
		_E \
		_F \
		_G \
		_H \
		_I \
		_J \
		_Z
	}

	# The calling application may export shell variables named by
	# prefixing table variable names with 'i18n_col_', each containing
	# the translated value of a column header.

	while read v; do
		export i18n_col_$v=${v@L}
	done < <(app_tbl_col_vars_generator)

	# Helpers

	section() {
		printf '\n\033[7m %s \033[0m\n' "$*"
	}
	cmd() {
		printf '> %s\n' "$*"
	}
	show() {
		local -
		set -o pipefail
		tbl_print '|' flag | column -s '|' -t
	}

	#################
	#  TABLE SETUP  #
	#################

	rm -f /tmp/the.tbl /tmp/col_vars /tmp/col_nums /tmp/col_hdrs

	# Calls app_tbl_col_vars_generator.
	tbl_fetch_col_vars "/tmp/col_vars" "/tmp/col_nums" "/tmp/col_hdrs" ||
		return 1

	# The set of col_vars drives the declaration of global variables.
	tbl_declare_globals "/tmp/col_vars" "/tmp/col_nums"

	# Including headers from col_vars or col_hdrs is optional.
	# The headers below take the immutable row numbers 1 and 2.
	(
		tr '\n' '|' < /tmp/col_vars
		echo
		tr '\n' '|' < /tmp/col_hdrs
		echo
	) >  /tmp/the.tbl

	# Some application-specific code generates table cells.
	cat >> /tmp/the.tbl <<- EOF
	3:1|3:2|3:3|ddd|3 ee||||||
	4:1|4:2|4:3||4 ee||||i4||
	5:1|5:2|5:3||||1||i5||
	6:1|6:2|6:3|ddd||6:6|6:7||||
	7:1|7:2|7:3|ddd|||7:7||7:9||
	8:1|8:2|8:3||8 eee|||||j|
	9:1|9:2|9:3||9 ee||||||z
	EOF

	##############
	#  RUN DEMO  #
	##############

	section 'Load the application-generated table'
	cmd "tbl_load '|' < /tmp/the.tbl"
	cmd "tbl_get_active_range initial"
	tbl_load '|' < "/tmp/the.tbl"            &&
	tbl_get_active_range initial             || return 1

	section 'Show the table (columns aligned using `column -t`)'
	cmd "tbl_print '|' flag "
	show                                     || return 1

	section 'Filter rows using a shell conditional expression'
	cmd "tbl_filter '-n _J || _D == ddd'"
	tbl_filter '-n _J || _D == ddd'          &&
	show                                     || return 1

	section 'Filter rows using the immutable row numbers'
	cmd "tbl_slice '-2 -7'    # delete rows"
	tbl_slice '-2 -7'                        &&
	show                                     || return 1

	section 'Filter more'
	cmd "tbl_slice '2 -1'     # add/del rows"
	tbl_slice '2 -1'                         &&
	show                                     || return 1

	section 'Select columns'
	cmd "tbl_select '-* _B _E _J'"
	tbl_select '-* _B _E _J'                 &&
	show                                     || return 1

	section 'Select more, also using the immutable column number'
	cmd "tbl_select '-_J -_E 7'"
	tbl_select '-_J -_E 7'                   &&
	show                                     || return 1

	section 'Show the table complement'
	cmd "tbl_get_inactive_range inactive"
	cmd 'tbl_set_active_range "$inactive"'
	tbl_get_inactive_range inactive          &&
	tbl_set_active_range "$inactive"         &&
	show                                     || return 1

	section 'Restore the initial table'
	cmd 'tbl_set_active_range "$initial"'
	tbl_set_active_range "$initial"          &&
	show                                     || return 1

	section 'Bash for single cell <7,_I>'
	cmd 'echo "${col_I[7]}"'
	echo "${col_I[7]}"

	section 'Bash to traverse column _E'
	echo '# It starts with the immutable column number'
	cmd 'printf "| % 5s |\n" "${col_E[@]}"'
	printf "| % 5s |\n" "${col_E[@]}"

	section 'Bash to traverse row 9'
	echo '# This awkwardly complicated code is included for completeness.'
	echo '# Wrap it as a function for repeated use. Or, to implement traversal'
	echo '# without using `eval`, take inspiration from function tbl_print().'
	cat <<- \EOF
	> c=("${colV[@]/%/\[9\]\}\"}")
	> unset c[0]
	> c=("${c[@]/#/\"\${col}")
	> eval c=( "${c[@]}" )
	> printf " | %s" "${c[@]}"; echo
	EOF
	c=("${colV[@]/%/\[9\]\}\"}")
	unset c[0]
	c=("${c[@]/#/\"\${col}")
	eval c=( "${c[@]}" )
	printf " | %s" "${c[@]}"; echo

	section 'Fin'
	echo '# Nothing to show here'
	tbl_slice '-*'                           &&
	show                                     || return 1
}

tbl_demo
fi

# vim:ft=bash:ts=8:noet:sw=0:
