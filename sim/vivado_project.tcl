# vivado_project.tcl: point a Vivado GUI project at this repo's sources.
# Files are added by reference, never copied, so the project always shows the
# repo's current code. The source list comes from sim/files.f:
# rtl/ goes to sources_1, everything else to sim_1.
#
# Usage (Vivado closed):
#   vivado -mode batch -source sim/vivado_project.tcl -tclargs <project.xpr> [sim_top]
# Rerun it whenever sim/files.f changes. Files on disk are never deleted.

if {[llength $argv] < 1} {
  error "usage: -tclargs <project.xpr> \[sim_top\]"
}
set repo    [file normalize [file join [file dirname [info script]] ..]]
set xpr     [file normalize [lindex $argv 0]]
set sim_top [expr {[llength $argv] > 1 ? [lindex $argv 1] : "tb_l1_read"}]

open_project $xpr

# Remove every source from both filesets (this edits the project only).
foreach fs {sources_1 sim_1} {
  set old [get_files -quiet -of_objects [get_filesets $fs]]
  if {[llength $old] > 0} {
    remove_files -fileset $fs $old
  }
}

# Read the repo's source list.
set rtl {}
set tb  {}
set fh [open [file join $repo sim files.f] r]
foreach line [split [read $fh] "\n"] {
  set line [string trim $line]
  if {$line eq "" || [string index $line 0] eq "#"} { continue }
  set path [file join $repo $line]
  if {![file exists $path]} { error "missing source: $path" }
  if {[string match "rtl/*" $line]} { lappend rtl $path } else { lappend tb $path }
}
close $fh

add_files -norecurse -fileset sources_1 $rtl
add_files -norecurse -fileset sim_1     $tb

set_property top l1_cache [get_filesets sources_1]
set_property top $sim_top [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "vivado_project: [llength $rtl] RTL + [llength $tb] testbench files from $repo"
puts "vivado_project: sim top = $sim_top"
close_project
