# vim:ts=4 sw=4 fo=croq
# portarchive.tcl
#
# Copyright (c) 2004 Robert Shaw <rshaw@opendarwin.org>
# Copyright (c) 2002 - 2003 Apple Computer, Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the name of Apple Computer, Inc. nor the names of its contributors
#    may be used to endorse or promote products derived from this software
#    without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

package provide portarchive 1.0
package require portutil 1.0

set com.apple.archive [target_new com.apple.archive archive_main]
target_init ${com.apple.archive} archive_init
target_provides ${com.apple.archive} archive
target_requires ${com.apple.archive} main fetch extract checksum patch configure build destroot
target_prerun ${com.apple.archive} archive_start
target_postrun ${com.apple.archive} archive_finish

# defaults
default archive.dir {${destpath}}
default archive.env {}
default archive.cmd {}
default archive.pre_args {}
default archive.args {}
default archive.post_args {}

default archive.destpath {${portarchivepath}}
default archive.file {}
default archive.path {}

set_ui_prefix

proc archive_init {args} {
	global UI_PREFIX target_state_fd
	global variations package.destpath workpath portpath
	global ports_force ports_source_only ports_binary_only
	global portname portversion portrevision portvariants
	global archive.destpath archive.file archive.path

	# Check mode in case archive called directly by user
	if {[option portarchivemode] != "yes"} {
		return -code error "Archive mode is not enabled!"
	}

	# Define port variants if not already defined
	if { ![info exists portvariants] } {
		set portvariants ""
		set vlist [lsort -ascii [array names variations]]
		# Put together variants in the form +foo+bar for the archive name
		foreach v $vlist {
			if { ![string equal $v [option os.platform]] && ![string equal $v [option os.arch]] } {
				set portvariants "${portvariants}+${v}"
			}
		}
	}

	# Define archive destination directory and target filename
	if {![string equal ${archive.destpath} ${workpath}] && ![string equal ${archive.destpath} ""]} {
		set archive.destpath [file join ${archive.destpath} [option os.platform] [option os.arch]]
	}
	set archive.file "${portname}-${portversion}_${portrevision}${portvariants}.[option os.arch].[option portarchivetype]"
	set archive.path "[file join ${archive.destpath} ${archive.file}]"

	# Determine if archive should be skipped
	set skipped 0
	if {[check_statefile target com.apple.archive $target_state_fd]} {
		return 0
	} elseif {[check_statefile target com.apple.unarchive $target_state_fd] && ([info exists ports_binary_only] && $ports_binary_only == "yes")} {
		ui_debug "Skipping archive ($portname) since binary-only is set"
		set skipped 1
	} elseif {[info exists ports_source_only] && $ports_source_only == "yes"} {
		ui_debug "Skipping archive ($portname) since source-only is set"
		set skipped 1
	} elseif {[file readable ${archive.path}] && ([file mtime ${archive.path}] >= [file mtime [file join $portpath Portfile]]) && !([info exists ports_force] && $ports_force == "yes")} {
		#ui_msg "$UI_PREFIX [format [msgcat::mc "Archive for %s %s_%s%s is already up-to-date"] $portname $portversion $portrevision $portvariants]"
		#set skipped 1
		return -code error [format [msgcat::mc "Archive for %s %s_%s%s is already up-to-date"] $portname $portversion $portrevision $portvariants]
	}
	# Skip archive target by setting state
	if {$skipped == 1} {
		write_statefile target "com.apple.archive" $target_state_fd
	}

	return 0
}

proc archive_start {args} {
	global UI_PREFIX
	global portname portversion portrevision portvariants portpath
	global archive.env archive.cmd archive.pre_args archive.args archive.post_args
	global archive.path

	ui_msg "$UI_PREFIX [format [msgcat::mc "Packaging archive for %s %s_%s%s"] $portname $portversion $portrevision $portvariants]"

	# Define appropriate archive command and options
	switch -regex [option portarchivetype] {
		cp(io|gz) {
			set ditto "ditto"
			if {[catch {set ditto [binaryInPath $ditto]} errmsg] == 0} {
				ui_debug "Using $ditto"
				set archive.cmd "$ditto"
				set archive.pre_args {-c -v -V --rsrc}
				set archive.args ". ${archive.path}"
			} else {
				ui_debug $errmsg
				set cpio "cpio"
				if {[catch {set cpio [binaryInPath $cpio]} errmsg] == 0} {
					ui_debug "Using $cpio"
					set archive.cmd "find . -print | $cpio"
					set archive.pre_args {-o -v -c -H cpio}
					set archive.args "-O ${archive.path}"
				} else {
					ui_debug $errmsg
					return -code error "Neither '$ditto' or '$cpio' were found on this system!"
				}
			}
			if {[regexp {z$} [option portarchivetype]]} {
				set archive.pre_args "${archive.pre_args} -z"
			}
		}
		xar {
			set xar "xar"
			if {[catch {set xar [binaryInPath $xar]} errmsg] == 0} {
				ui_debug "Using $xar"
				set archive.cmd "$xar"
				set archive.pre_args {-cf}
				set archive.args "${archive.path} ."
			} else {
				ui_debug $errmsg
				return -code error "No '$xar' was found on this system!"
			}
		}
		t(ar|gz) {
			set gnutar "gnutar"
			if {[catch {set gnutar [binaryInPath $gnutar]} errmsg] == 0} {
				ui_debug "Using $gnutar"
				set archive.cmd "$gnutar"
				if {[regexp {z$} [option portarchivetype]]} {
					set archive.pre_args {-zcvf}
				} else {
					set archive.pre_args {-cvf}
				}
				set archive.args "${archive.path} ."
			} else {
				ui_debug $errmsg
				set gtar "gtar"
				if {[catch {set gtar [binaryInPath $gtar]} errmsg] == 0} {
					ui_debug "Using $gtar"
					set archive.cmd "$gtar"
					if {[regexp {z$} [option portarchivetype]]} {
						set archive.pre_args {-zcvf}
					} else {
						set archive.pre_args {-cvf}
					}
					set archive.args "${archive.path} ."
				} else {
					ui_debug $errmsg
					set tar "tar"
					if {[catch {set tar [binaryInPath $tar]} errmsg] == 0} {
						ui_debug "Using $tar"
						set archive.cmd "$tar"
						set archive.pre_args {-cvf}
						if {[regexp {z$} [option portarchivetype]]} {
							set gzip "gzip"
							if {[catch {set gzip [binaryInPath $gzip]} errmsg] == 0} {
								ui_debug "Using $gzip"
								set archive.args {- .}
								set archive.post_args "| $gzip -c > ${archive.path}"
							} else {
								ui_debug $errmsg
								return -code error "No '$gzip' was found on this system!"
							}
						} else {
							set archive.args "${archive.path} ."
						}
					} else {
						ui_debug $errmsg
						return -code error "None of '$gnutar', '$gtar', or '$tar' were found on this system!"
					}
				}
			}
		}
		default {
			return -code error "Invalid port archive type '[option portarchivetype]' specified!"
		}
	}

	return 0
}

proc archive_main {args} {
	global UI_PREFIX
	global workpath destpath
	global portname portversion portrevision portvariants
	global archive.destpath archive.path archive.file

	# Remove existing archive
	if {[file exists ${archive.path}]} {
		ui_info "$UI_PREFIX [format [msgcat::mc "Deleting previous %s"] ${archive.file}]"
		file delete -force ${archive.path}
	}

	# Create archive destination path (if needed)
	if {![file isdirectory ${archive.destpath}]} {
		system "mkdir -p ${archive.destpath}"
	}

	# Copy state file into destroot for archiving
	# +STATE contains a copy of the DP state information
    set statefile [file join $workpath .darwinports.${portname}.state]
	file copy -force $statefile [file join $destpath "+STATE"]

	# Create some informational files that we don't really use just yet,
	# but we may in the future in order to allow port installation from
	# archives without a full "dports" tree of Portfiles.
	#
	# Note: These have been modeled after FreeBSD type package files to
	# start. We can change them however we want for actual future use if
	# needed.
	#
	# +COMMENT contains the port description
	set fd [open [file join $destpath "+COMMENT"] w]
    if {[exists description]} {
		puts $fd "[option description]"
	}
	close $fd
	# +DESC contains the port long_description and homepage
	set fd [open [file join $destpath "+DESC"] w]
	if {[exists long_description]} {
		puts $fd "[option long_description]"
	}
	if {[exists homepage]} {
		puts $fd "\nWWW: [option homepage]"
	}
	close $fd
	# +CONTENTS contains the port version/name info and all installed
	# files and checksums
	set control [list]
	set fd [open [file join $destpath "+CONTENTS"] w]
	puts $fd "@name ${portname}-${portversion}_${portrevision}${portvariants}"
	foreach fullpath [exec find $destpath ! -type d] {
		set relpath [strsed $fullpath "s|^$destpath/||"]
		if {![regexp {^[+]} $relpath]} {
			puts $fd "$relpath"
			if {[file isfile $fullpath]} {
				ui_debug "checksum file: $fullpath"
				set checksum [md5 file $fullpath]
				puts $fd "@comment MD5:$checksum"
			}
		} else {
			lappend control $relpath
		}
	}
	foreach relpath $control {
		puts $fd "@ignore"
		puts $fd "$relpath"
	}
	close $fd

	# Now create the archive
	ui_info "$UI_PREFIX [format [msgcat::mc "Creating %s"] ${archive.file}]"
    system "[command archive]"
    return 0
}

proc archive_finish {args} {
	global UI_PREFIX
	global destpath archive.file

	# Cleanup all control files when finished
	set control_files [glob -nocomplain -types f [file join $destpath +*]]
	foreach file $control_files {
		ui_debug "removing file: $file"
		file delete -force $file
	}

	ui_info "$UI_PREFIX [format [msgcat::mc "Archive %s packaged"] ${archive.file}]"
	return 0
}

