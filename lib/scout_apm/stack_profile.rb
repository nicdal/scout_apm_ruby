require 'stack_profile'

class StackProfile
  def self.hello
    puts "hello"
  end
end

ScoutApm.after_gc_start_hook = proc { p "GC START" ; p GC.stat ; p StackProfile.getstack }
ScoutApm.after_gc_end_hook = proc { p "GC END" ; p GC.stat ; p StackProfile.getstack }