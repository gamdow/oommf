# FILE: eventhandler.tcl
#
# The Oc_Class Oc_EventHandler handles events generated by instance of 
# Oc_Classes in a manner analogous to the way the Tk commands bind, 
# bindtags, and event handle events generated by Tk windows.
#
# Each Oc_EventHandler instance stores a binding tag, an event
# identifier, and a Tcl script, indicating that when the event named by
# the identifier occurs in an object tagged with the binding 
# tag, the script should be evaluated to handle the event.  By default
# each object is tagged with its name ($this) and its class ($class).
# The tags of an object can be modified via the 'Oc_EventHandler Bindtags'
# command, analogous to the Tk bindtags command.
#
# Some care may need to be taken that when the invocation of an eventHandler
# generates new events, the recursion has a 'bottom' so an infinite loop
# is not entered.
#
# Binding tags and event id's may be any non-empty string.
#
# Last modified on: $Date: 2015/09/11 03:09:45 $
# Last modified by: $Author: donahue $

Oc_Class Oc_EventHandler {

    # A map from (tag,event) pairs to handler lists
    array common map

    # A map from group names to handler lists
    array common groupmap

    # A map from object names to their binding tags
    array common bindtags

    proc Bindtags {object args} {bindtags} {
        set numargs [llength $args]
        if {$numargs == 0} {
            if {[info exists bindtags($object)]} {
                return $bindtags($object)
            } else {
                return
            }
        }
        if {$numargs == 1} {
            if {[catch {lrange [lindex $args 0] 0 end} taglist]} {
                return -code error "<taglist> must be a proper Tcl list"
            }
            if {[llength $taglist]} {
                set bindtags($object) $taglist
            } else {
                catch {unset bindtags($object)}
            }
            return
        }
        return -code error "usage: $class Bindtags <object> ?<taglist>?"
    }

    proc Generate {object event args} {bindtags map} {
        if {[catch {set bindtags($object)} taglist]} {
            # No bindings --> nothing to do
            return
        }
        array set option [list %% % %object $object]
        foreach {opt val} $args {
            if {[regexp {^-([a-zA-Z0-9_]+)$} $opt m opt]} {
                set option(%$opt) [list $val]
            } else {
                return -code error "Invalid option: $opt"
            }
        }
        foreach tag $taglist {
            Oc_Log Log "Event: $tag $event" status $class
            if {[info exists map($tag,$event)]} {
                set handlers $map($tag,$event)
                foreach handler $handlers {
                    # Have to check existence of handler, because eval-ing
                    # one handler in the list may have the effect of deleting
                    # a later handler in the list.
                    if {![catch {$handler Script} script]} {
                        # If -oneshot is true, then delete handler
                        # before running it --- else the handler may
                        # loop back and re-trigger before it is
                        # deleted.
                        if {[$handler Cget -oneshot]} {
                           if {[catch {$handler Delete} dmsg]} {
                              global errorInfo
                              append errorInfo "\n    (deleting -oneshot\
                                        $class)\n    ($class for\
                                        (tag,event): '($tag,$event)')"
                              bgerror $dmsg
                           }
                        }
                        # Percent substitutions
                        if {[regexp % $script]} {
                            regsub -all {[\$]} $script {\\&} _
                            regsub -all {%(%|[a-zA-Z0-9_]+)} $_ {$option(&)} _
                            if {[catch {set script [subst -nocommands $_]}]} {
                                global errorInfo errorCode
                                set errorCode [list OC $class]
                                set errorInfo "Can't complete substitutions\
                                        in $class script\nfor (tag,event):\
                                        '($tag,$event)':\n    [subst \
                                        -nocommands -novariables \
                                        $script]\nMissing option to $class\
                                        Generate?\nAvailable substitutions:\
                                        \n    [array names option]"
                                bgerror $errorInfo
                                set code 4
                            } else {
                                set code [catch {uplevel #0 $script} msg]
                            }
                        } else {
                            set code [catch {uplevel #0 $script} msg]
                        }
                        if {$code == 1} {
                            global errorInfo errorCode
                            foreach {ei ec} [list $errorInfo $errorCode] {}
                        }
                        switch -exact -- $code {
                            0 {;# ok
                                # Do nothing
                            }
                            1 {;# error -- Use bgerror to report the error
                                set errorCode $ec
                                set index [string last " (\"uplevel" $ei]
                                set errorInfo [string trimright [string \
                                        range $ei 0 $index]]
                                append errorInfo "\n    ($class for\
                                        (tag,event): '($tag,$event)')"
                                bgerror $msg
                                # Then continue with the next handler
                            }
                            2 {;# return -- end event handler processing
                                return
                            }
                            3 {;# break -- break out of inner loop
                                # Process handler for the next tag
                                break
                            }
                            4 {;# continue
                                # Do nothing -- just continue to next iteration
                            }
                        }
                    }
                }
            }
        }
    }

    proc Bindings {tag args} {map} {
        set numargs [llength $args]
        if {$numargs == 0} {
            set ret {}
            foreach pair [array names map $tag,*] {
                lappend ret [string range $pair [string length $tag,] end]
            }
            return $ret
        }
        if {$numargs == 1} {
            set event [lindex $args 0]
            if {[catch {set map($tag,$event)} handlers]} {
                return
            }
            return $handlers
        }
        return -code error "usage: $class Bindings <tag> ?<event>?"
    }

    # Cleanup for a whole set of handlers at a time.
    proc DeleteGroup { grp } {groupmap} {
        if {[catch {set groupmap($grp)} handlers]} {
            return
        }
        foreach handler $handlers {
            $handler Delete
        }
    }

    # The binding tag for this handler instance
    private variable tag

    # The event identifier for this handler instance
    private variable event

    # The script to evaluate to handle the event
    private variable script

    # Boolean indicating whether this handler should only execute once
    # and then self-destruct.
    const public variable oneshot = 0

    # The groups to which this handler belongs, for cleanup purposes
    const public variable groups = {}

    Constructor {_tag _event _script {position end} args} {
        if {[string match {} $_tag]} {
            return -code error "The binding tag must be non-empty"
        } else {
            set tag $_tag
        }
        if {[string match {} $_event]} {
            return -code error "The event id must be non-empty"
        } else {
            set event $_event
        }
        if {[info complete $_script]} {
            set script $_script
        } else {
            return -code error "The handler script provided is not\
                    a complete Tcl command:\n\t$_script"
        }
        if {[string match -* $position]} {
            eval $this Configure $position $args
            set position end
        } else {
            eval $this Configure $args
        }
        # Register self on appropriate list of event handlers
        if {[catch {set map($tag,$event)} handlers]} {
            set handlers {}
        }
        set map($tag,$event) [linsert $handlers $position $this]
        # Register self on appropriate group lists
        foreach grp $groups {
            if {[catch {set groupmap($grp)} handlers]} {
                set handlers {}
            }
            set groupmap($grp) [linsert $handlers end $this]
        }
    }

    private method Script {} {
        return $script
    }

    Destructor {
        # Deregister self on appropriate list of event handlers
        set handlers $map($tag,$event)
        set i [lsearch -exact $handlers $this]
        if {$i < 0} {
            error "Programming error: $class $this disappeared!"
        } else {
            set newlist [lreplace $handlers $i $i]
            if {[llength $newlist]} {
                set map($tag,$event) $newlist
            } else {
                unset map($tag,$event)
            }
        }
        # Deregister self on appropriate group list(s)
        foreach grp $groups {
            set handlers $groupmap($grp)
            set i [lsearch -exact $handlers $this]
            if {$i < 0} {
                error \
"Programming error: $class $this not in group list for $grp!"
            } else {
                set newlist [lreplace $handlers $i $i]
                if {[llength $newlist]} {
                    set groupmap($grp) $newlist
                } else {
                    unset groupmap($grp)
                }
            }
        }
    }
  
}

