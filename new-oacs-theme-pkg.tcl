#!/home/mu-dev/inst/bin/tclsh8.4

# Synopsis:
#
#    new-oacs-theme-pkg.tcl <servRoot> <pkgNameStem>
#
# copies content of package openacs-default-theme to
# new package <pkgNameStem> which cannot end in "-theme"
# and <pkgNameStem>-theme must not exist in 
# <servRoot>/packages, otherwise the attempt is an error,
# and nothing will happen.
#
# if successful, there will be a new package located in
# <servRoot>/packages/<pkgNameStem>-theme whose files are present
# and correct, but is not known to the service in 
# <servRoot>, so you would then have to restart the 
# service, install the package via the apm and then 
# restart again.
#
# Once installed into the service, the following will then
# be available:
#   - a theme object whose key is <pkgNameStem>-plain
#   - another named <pkgNameStem>-tabbed
# (either of these would go in the ThemeKey parameter of 
# the subsite which will use this theme. more:)
#   - /packages/<pkgNameStem>-theme/lib/plain-master
# (for param Theming/DefaultMaster)
#   - /resources/<pkgNameStem>-theme/styles/default-master.css
# (as part of the string value of ThemeCSS)

set servRoot [lindex $argv 0]
set pkgNameStem [lindex $argv 1]
set pkgName "$pkgNameStem-theme"
set origPkgName "openacs-default-theme"

if {[llength $argv] !=2} {
    puts stderr "usage: $argv0 <servRoot> <pkgNameStem>"
    exit 1
}

if {[file exists "${servRoot}/packages/${pkgName}"]} {
    puts stderr "$argv0: you already have ${pkgName}"
    puts stderr "$argv0: in ${servRoot}/packages/. cannot continue."
    exit 1
}

if {[regexp -- "-theme$" $pkgNameStem match]} {
    puts \
        stderr \
        "$argv0: pkgNameStem shouldn't end with -theme"
    exit 1
}

file copy \
    "$servRoot/packages/$origPkgName" \
    "$servRoot/packages/$pkgName"

set infoChannel [open "${servRoot}/packages/$origPkgName/$origPkgName.info"]
set infotxt [read $infoChannel]
close $infoChannel

package require tdom

set infodom [dom parse $infotxt]
set infoRoot [$infodom documentElement]

proc mk_underscore_names {origPkg newPkg origPkgUn newPkgUn} {
    upvar $origPkgUn origPkgUnderscores
    upvar $newPkgUn newPkgUnderscores

    set origPkgUnderscores \
        [regsub \
            -all \
            -- \
            "-" \
            $origPkg \
            "_"]
    set newPkgUnderscores \
        [regsub \
            -all \
            -- \
            "-" \
            $newPkg \
            "_"]
}

proc xmlSubst {parent origPkg newPkg} {
    set type [$parent nodeType]
    set name [$parent nodeName]
    set value [$parent nodeValue]
    mk_underscore_names \
        $origPkg \
        $newPkg \
        origPkgUnderscores \
        newPkgUnderscores

    if {$type != "ELEMENT_NODE"} then return

    regsub -- $origPkg $value $newPkg newValue
    # $parent nodeValue $newValue
 
    set attribs [$parent attributes]
 
    if {[llength $attribs]} {

        foreach attrib $attribs {
            set aValue [$parent getAttribute $attrib ""]

            regsub -- $origPkg $aValue $newPkg interValue
            regsub -- $origPkgUnderscores $interValue $newPkgUnderscores newValue
            $parent setAttribute $attrib $newValue
        }
    }
 
    foreach child [$parent childNodes] {
        xmlSubst $child $origPkg $newPkg
    }
}

proc plainTextSubst {fileName origPkg newPkg} {
    mk_underscore_names \
        $origPkg \
        $newPkg \
        origPkgUnderscores \
        newPkgUnderscores

    set inChan [open $fileName]
    set txt [read $inChan]
    close $inChan

    regsub -all "$origPkg" $txt "$newPkg" txt
    regsub -all "$origPkgUnderscores" $txt "$newPkgUnderscores" txt

    set outChan [open $fileName "w"]
    puts -nonewline $outChan $txt
    close $outChan
}

proc explore {parent indent} {
    set type [$parent nodeType]
    set name [$parent nodeName]
    set value [$parent nodeValue]
 
    puts "$indent$parent is a $type node named $name with value $value"

    if {$type != "ELEMENT_NODE"} then return

    set attribs [$parent attributes]
 
    if {[llength $attribs]} {
        set attrList [list]

        foreach attrib $attribs {
            set aValue [$parent getAttribute $attrib ""]

            append attrList "$attrib=\"$aValue\""
        }

        puts "${indent}attribs: [join $attrList {, }]"
    }
 
    foreach child [$parent childNodes] {
        explore $child "$indent  "
    }
}

# explore $infoRoot ""
xmlSubst $infoRoot $origPkgName $pkgName
# explore $infoRoot ""

set infoxml [$infoRoot asXML]

set infoOutChannel \
    [open \
        "$servRoot/packages/$pkgName/$pkgName.info" \
        "w"]

puts $infoOutChannel $infoxml
close $infoOutChannel
file delete "$servRoot/packages/$pkgName/$origPkgName.info"

proc findFiles {root} {
    set dirs \
        [glob \
            -type d \
            -directory $root \
            -nocomplain \
            *]

    set files \
        [glob \
            -type f \
            -directory $root \
            -nocomplain \
            *]

    foreach dir $dirs {
        set files \
            [concat \
                $files \
                [findFiles $dir]]
    }

    return $files
}

# all files (not dirs) in the new package
set pkgFiles [findFiles "$servRoot/packages/$pkgName/"]

# remove info file from list
set infoFile [lsearch -inline -glob $pkgFiles "*.info"]
set pkgFiles [lsearch -all -inline -exact -not $pkgFiles $infoFile]

# remove .gifs
set gifFiles [lsearch -all -inline -glob $pkgFiles "*.gif"]
foreach gifFile $gifFiles {
    set pkgFiles \
        [lsearch \
            -all -inline -exact -not \
            $pkgFiles \
            $gifFile]
}

# pull .xml files from pkgFiles into xmlFiles
set xmlFiles [lsearch -all -inline -glob $pkgFiles "*.xml"]
foreach xmlFile $xmlFiles {
    set pkgFiles \
        [lsearch \
            -all -inline -exact -not \
            $pkgFiles \
            $xmlFile]
}

# process the files in pkgFiles as plain text

foreach pkgFile $pkgFiles {
    plainTextSubst $pkgFile $origPkgName $pkgName
}

