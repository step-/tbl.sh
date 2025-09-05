# tbl.sh - Minimalistic Bash Data Table Library

Homepage: <https://github.com/step-/tbl.sh>

## Design Choices

- Multiple data tables can exist as separate files but only one can be
  loaded into memory at a time, simplifying global state management.

- Immutable row and column numbers are the positive indices of the
  rows/columns of the table; these never change after loading.

- The active range is the subset of immutable row/column numbers identifying
  the visible rows/columns at any one point.

- Table functions accept immutable row/column numbers as arguments, and
  operate on the active range internally.

- The active range is initialized to include all input rows and columns
  upon loading the table via `tbl_load()`.

- Functions like `tbl_filter()` and `tbl_slice()` for rows, and `tbl_select()`
  for columns modify the active range to show or hide elements by adding
  or removing their public numbers from the active range.

- Function `tbl_print()` outputs the table restricted by the active range.
- The current active range can be saved and restored, allowing for reversible
  operations and state management.

## Usage

Copy the tbl.sh and LICENSE files into your project, source tbl.sh in your bash
main function and you are ready to go.

The library includes a demo mode to illustrate how to use it. Here is its output.

 **Load the application-generated table**

```sh
> tbl_load '|' < /tmp/the.tbl
> tbl_get_active_range initial
```

 **Show the table (columns aligned using `column -t`)**

```sh
> tbl_print '|' flag
_A   _B   _C   _D    _E     _F    _G    _H    _I    _J    _Z
_a   _b   _c   _d    _e     _f    _g    _h    _i    _j    _z
3:1  3:2  3:3  ddd   3 ee   flag  flag  flag  flag  flag  flag
4:1  4:2  4:3  flag  4 ee   flag  flag  flag  i4    flag  flag
5:1  5:2  5:3  flag  flag   flag  1     flag  i5    flag  flag
6:1  6:2  6:3  ddd   flag   6:6   6:7   flag  flag  flag  flag
7:1  7:2  7:3  ddd   flag   flag  7:7   flag  7:9   flag  flag
8:1  8:2  8:3  flag  8 eee  flag  flag  flag  flag  j     flag
9:1  9:2  9:3  flag  9 ee   flag  flag  flag  flag  flag  z
```

 **Filter rows using a shell conditional expression**

```sh
> tbl_filter '-n _J || _D == ddd'
_A   _B   _C   _D    _E     _F    _G    _H    _I    _J    _Z
_a   _b   _c   _d    _e     _f    _g    _h    _i    _j    _z
3:1  3:2  3:3  ddd   3 ee   flag  flag  flag  flag  flag  flag
6:1  6:2  6:3  ddd   flag   6:6   6:7   flag  flag  flag  flag
7:1  7:2  7:3  ddd   flag   flag  7:7   flag  7:9   flag  flag
8:1  8:2  8:3  flag  8 eee  flag  flag  flag  flag  j     flag
```

 **Filter rows using the immutable row numbers**

```sh
> tbl_slice '-2 -7'    # delete rows
_A   _B   _C   _D    _E     _F    _G    _H    _I    _J    _Z
3:1  3:2  3:3  ddd   3 ee   flag  flag  flag  flag  flag  flag
6:1  6:2  6:3  ddd   flag   6:6   6:7   flag  flag  flag  flag
8:1  8:2  8:3  flag  8 eee  flag  flag  flag  flag  j     flag
```

 **Filter more**

```sh
> tbl_slice '2 -1'     # add/del rows
_a   _b   _c   _d    _e     _f    _g    _h    _i    _j    _z
3:1  3:2  3:3  ddd   3 ee   flag  flag  flag  flag  flag  flag
6:1  6:2  6:3  ddd   flag   6:6   6:7   flag  flag  flag  flag
8:1  8:2  8:3  flag  8 eee  flag  flag  flag  flag  j     flag
```

 **Select columns**

```sh
> tbl_select '-* _B _E _J'
_b   _e     _j
3:2  3 ee   flag
6:2  flag   flag
8:2  8 eee  j
```

 **Select more, also using the immutable column number**

```sh
> tbl_select '-_J -_E 7'
_b   _g
3:2  flag
6:2  6:7
8:2  flag
```

 **Show the table complement**

```sh
> tbl_get_inactive_range inactive
> tbl_set_active_range "$inactive"
_A   _C   _D    _E    _F    _H    _I    _J    _Z
4:1  4:3  flag  4 ee  flag  flag  i4    flag  flag
5:1  5:3  flag  flag  flag  flag  i5    flag  flag
7:1  7:3  ddd   flag  flag  flag  7:9   flag  flag
9:1  9:3  flag  9 ee  flag  flag  flag  flag  z
```

 **Restore the initial table**

```sh
> tbl_set_active_range "$initial"
_A   _B   _C   _D    _E     _F    _G    _H    _I    _J    _Z
_a   _b   _c   _d    _e     _f    _g    _h    _i    _j    _z
3:1  3:2  3:3  ddd   3 ee   flag  flag  flag  flag  flag  flag
4:1  4:2  4:3  flag  4 ee   flag  flag  flag  i4    flag  flag
5:1  5:2  5:3  flag  flag   flag  1     flag  i5    flag  flag
6:1  6:2  6:3  ddd   flag   6:6   6:7   flag  flag  flag  flag
7:1  7:2  7:3  ddd   flag   flag  7:7   flag  7:9   flag  flag
8:1  8:2  8:3  flag  8 eee  flag  flag  flag  flag  j     flag
9:1  9:2  9:3  flag  9 ee   flag  flag  flag  flag  flag  z
```

 **Bash for single cell <7,_I>**

```sh
> echo "${col_I[7]}"
7:9
```

 **Bash to traverse column _E**

```sh
# It starts with the immutable column number
> printf "| % 5s |\n" "${col_E[@]}"
|     5 |
|    _E |
|    _e |
|  3 ee |
|  4 ee |
|       |
|       |
|       |
| 8 eee |
|  9 ee |
```

 **Bash to traverse row 9**

```sh
# This awkwardly complicated code is included for completeness.
# Wrap it as a function for repeated use. Or, to implement traversal
# without using `eval`, take inspiration from function tbl_print().
> c=("${colV[@]/%/\[9\]\}\"}")
> unset c[0]
> c=("${c[@]/#/\"\${col}")
> eval c=( "${c[@]}" )
> printf " | %s" "${c[@]}"; echo
 | 9:1 | 9:2 | 9:3 |  | 9 ee |  |  |  |  |  | z
```

 **Fin**
