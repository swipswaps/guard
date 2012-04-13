require 'spec_helper'

describe Guard do

  it "has a valid Guardfile template" do
    File.exists?(Guard::GUARDFILE_TEMPLATE).should be_true
  end

  describe ".create_guardfile" do
    before { Dir.stub(:pwd).and_return "/home/user" }

    context "with an existing Guardfile" do
      before { File.should_receive(:exist?).and_return true }

      it "does not copy the Guardfile template or notify the user" do
        ::Guard::UI.should_not_receive(:info)
        FileUtils.should_not_receive(:cp)

        subject.create_guardfile
      end

      it "does not display any kind of error or abort" do
        ::Guard::UI.should_not_receive(:error)
        subject.should_not_receive(:abort)
        subject.create_guardfile
      end

      context "with the :abort_on_existence option set to true" do
        it "displays an error message and aborts the process" do
          ::Guard::UI.should_receive(:error).with("Guardfile already exists at /home/user/Guardfile")
          subject.should_receive(:abort)
          subject.create_guardfile(:abort_on_existence => true)
        end
      end
    end

    context "without an existing Guardfile" do
      before { File.should_receive(:exist?).and_return false }

      it "copies the Guardfile template and notifies the user" do
        ::Guard::UI.should_receive(:info)
        FileUtils.should_receive(:cp)

        subject.create_guardfile
      end
    end
  end

  describe ".initialize_template" do
    context 'with an installed Guard implementation' do
      let(:foo_guard) { double('Guard::Foo').as_null_object }

      before { ::Guard.should_receive(:get_guard_class).and_return(foo_guard) }

      it "initializes the Guard" do
        foo_guard.should_receive(:init)
        subject.initialize_template('foo')
      end
    end

    context "with a user defined template" do
      let(:template) { File.join(Guard::HOME_TEMPLATES, '/bar') }

      before { File.should_receive(:exist?).with(template).and_return true }

      it "copies the Guardfile template and initializes the Guard" do
        File.should_receive(:read).with('Guardfile').and_return 'Guardfile content'
        File.should_receive(:read).with(template).and_return 'Template content'
        io = StringIO.new
        File.should_receive(:open).with('Guardfile', 'wb').and_yield io
        subject.initialize_template('bar')
        io.string.should eql "Guardfile content\n\nTemplate content\n"
      end
    end

    context "when the passed guard can't be found" do
      before do
        ::Guard.should_receive(:get_guard_class).and_return nil
        File.should_receive(:exist?).and_return false
      end

      it "notifies the user about the problem" do
        ::Guard::UI.should_receive(:error).with(
          "Could not load 'guard/foo' or '~/.guard/templates/foo' or find class Guard::Foo"
        )
        subject.initialize_template('foo')
      end
    end
  end

  describe ".initialize_all_templates" do
    let(:guards) { ['rspec', 'spork', 'phpunit'] }

    before { subject.should_receive(:guard_gem_names).and_return(guards) }

    it "calls Guard.initialize_template on all installed guards" do
      guards.each do |g|
        subject.should_receive(:initialize_template).with(g)
      end

      subject.initialize_all_templates
    end
  end

  describe ".setup" do
    before do
      Guard::Dsl.stub(:evaluate_guardfile)
    end
    subject { ::Guard.setup }

    it "returns itself for chaining" do
      subject.should be ::Guard
    end

    it "initializes @guards" do
      subject.guards.should eql []
    end

    it "initializes @groups" do
      subject.groups[0].name.should eql :default
      subject.groups[0].options.should == {}
    end

    it "initializes the options" do
      opts = { :my_opts => true }
      Guard.setup(opts).options.should include(:my_opts)
    end

    it "initializes the listener" do
      ::Guard.listener.should be_kind_of(Listen::Listener)
    end

    it "respect the watchdir option" do
      ::Guard.setup(:watchdir => "/usr")
      ::Guard.listener.directory.should eql "/usr"
    end

    it "logs command execution if the debug option is true" do
      ::Guard.should_receive(:debug_command_execution)
      ::Guard.setup(:verbose => true)
    end

    it "evaluates the DSL" do
      ::Guard::Dsl.should_receive(:evaluate_guardfile)
      ::Guard.setup
    end

    it "displays an error message when no guard are defined in Guardfile" do
      ::Guard::Dsl.should_receive(:evaluate_guardfile)
      ::Guard::UI.should_receive(:error)
      ::Guard.setup
    end

    context "with interactions enabled" do
      it "fabricates the interactor" do
        ::Guard::Interactor.should_receive(:fabricate)
        ::Guard.setup(:no_interactions => false)
      end

      it "starts the interactor" do
        interactor = mock('interactor')
        interactor.should_receive(:start)
        ::Guard::Interactor.should_receive(:fabricate).and_return interactor
        ::Guard.setup(:no_interactions => false)
      end
    end

    context "with interactions disabled" do
      it "fabricates the interactor" do
        ::Guard::Interactor.should_not_receive(:fabricate)
        ::Guard.setup(:no_interactions => true)
      end
    end

    unless windows?
      context 'when receiving SIGUSR1' do
        context 'when Guard is running' do
          before { ::Guard.listener.should_receive(:paused?).and_return false }

          it 'pauses Guard' do
            ::Guard.should_receive(:pause)
            Process.kill :USR1, Process.pid
            sleep 1
          end
        end

        context 'when Guard is already paused' do
          before { ::Guard.listener.should_receive(:paused?).and_return true }

          it 'does not pauses Guard' do
            ::Guard.should_not_receive(:pause)
            Process.kill :USR1, Process.pid
            sleep 1
          end
        end
      end

      context 'when receiving SIGUSR2' do
        context 'when Guard is paused' do
          before { ::Guard.listener.should_receive(:paused?).and_return true }

          it 'un-pause Guard' do
            ::Guard.should_receive(:pause)
            Process.kill :USR2, Process.pid
            sleep 1
          end
        end

        context 'when Guard is already running' do
          before { ::Guard.listener.should_receive(:paused?).and_return false }

          it 'does not un-pause Guard' do
            ::Guard.should_not_receive(:pause)
            Process.kill :USR2, Process.pid
            sleep 1
          end
        end
      end
    end

    context "with the notify option enabled" do
      context 'without the environment variable GUARD_NOTIFY set' do
        before { ENV["GUARD_NOTIFY"] = nil }

        it "turns on the notifier on" do
          ::Guard::Notifier.should_receive(:turn_on)
          ::Guard.setup(:notify => true)
        end
      end

      context 'with the environment variable GUARD_NOTIFY set to true' do
        before { ENV["GUARD_NOTIFY"] = 'true' }

        it "turns on the notifier on" do
          ::Guard::Notifier.should_receive(:turn_on)
          ::Guard.setup(:notify => true)
        end
      end

      context 'with the environment variable GUARD_NOTIFY set to false' do
        before { ENV["GUARD_NOTIFY"] = 'false' }

        it "turns on the notifier off" do
          ::Guard::Notifier.should_receive(:turn_off)
          ::Guard.setup(:notify => true)
        end
      end
    end

    context "with the notify option disable" do
      context 'without the environment variable GUARD_NOTIFY set' do
        before { ENV["GUARD_NOTIFY"] = nil }

        it "turns on the notifier off" do
          ::Guard::Notifier.should_receive(:turn_off)
          ::Guard.setup(:notify => false)
        end
      end

      context 'with the environment variable GUARD_NOTIFY set to true' do
        before { ENV["GUARD_NOTIFY"] = 'true' }

        it "turns on the notifier on" do
          ::Guard::Notifier.should_receive(:turn_off)
          ::Guard.setup(:notify => false)
        end
      end

      context 'with the environment variable GUARD_NOTIFY set to false' do
        before { ENV["GUARD_NOTIFY"] = 'false' }

        it "turns on the notifier off" do
          ::Guard::Notifier.should_receive(:turn_off)
          ::Guard.setup(:notify => false)
        end
      end
    end
  end

  describe ".guards" do
    before(:all) do
      class Guard::FooBar < Guard::Guard; end
      class Guard::FooBaz < Guard::Guard; end
    end

    after(:all) do
      ::Guard.instance_eval do
        remove_const(:FooBar)
        remove_const(:FooBaz)
      end
    end

    subject do
      guard = ::Guard.setup
      @guard_foo_bar_backend  = Guard::FooBar.new([], { :group => 'backend' })
      @guard_foo_bar_frontend = Guard::FooBar.new([], { :group => 'frontend' })
      @guard_foo_baz_backend  = Guard::FooBaz.new([], { :group => 'backend' })
      @guard_foo_baz_frontend = Guard::FooBaz.new([], { :group => 'frontend' })
      guard.instance_variable_get("@guards").push(@guard_foo_bar_backend)
      guard.instance_variable_get("@guards").push(@guard_foo_bar_frontend)
      guard.instance_variable_get("@guards").push(@guard_foo_baz_backend)
      guard.instance_variable_get("@guards").push(@guard_foo_baz_frontend)
      guard
    end

    it "return @guards without any argument" do
      subject.guards.should eql subject.instance_variable_get("@guards")
    end

    describe "find a guard by as string/symbol" do
      it "find a guard by a string" do
        subject.guards('foo-bar').should eql @guard_foo_bar_backend
      end

      it "find a guard by a symbol" do
        subject.guards(:'foo-bar').should eql @guard_foo_bar_backend
      end

      it "returns nil if guard is not found" do
        subject.guards('foo-foo').should be_nil
      end
    end

    describe "find guards matching a regexp" do
      it "with matches" do
        subject.guards(/^foobar/).should eql [@guard_foo_bar_backend, @guard_foo_bar_frontend]
      end

      it "without matches" do
        subject.guards(/foo$/).should eql []
      end
    end

    describe "find guards by their group" do
      it "group name is a string" do
        subject.guards(:group => 'backend').should eql [@guard_foo_bar_backend, @guard_foo_baz_backend]
      end

      it "group name is a symbol" do
        subject.guards(:group => :frontend).should eql [@guard_foo_bar_frontend, @guard_foo_baz_frontend]
      end

      it "returns [] if guard is not found" do
        subject.guards(:group => :unknown).should eql []
      end
    end

    describe "find guards by their group & name" do
      it "group name is a string" do
        subject.guards(:group => 'backend', :name => 'foo-bar').should eql [@guard_foo_bar_backend]
      end

      it "group name is a symbol" do
        subject.guards(:group => :frontend, :name => :'foo-baz').should eql [@guard_foo_baz_frontend]
      end

      it "returns [] if guard is not found" do
        subject.guards(:group => :unknown, :name => :'foo-baz').should eql []
      end
    end
  end

  describe ".groups" do
    subject do
      guard = ::Guard.setup
      @group_backend  = guard.add_group(:backend)
      @group_backflip = guard.add_group(:backflip)
      guard
    end

    it "return @groups without any argument" do
      subject.groups.should eql subject.instance_variable_get("@groups")
    end

    describe "find a group by as string/symbol" do
      it "find a group by a string" do
        subject.groups('backend').should eql @group_backend
      end

      it "find a group by a symbol" do
        subject.groups(:backend).should eql @group_backend
      end

      it "returns nil if group is not found" do
        subject.groups(:foo).should be_nil
      end
    end

    describe "find groups matching a regexp" do
      it "with matches" do
        subject.groups(/^back/).should eql [@group_backend, @group_backflip]
      end

      it "without matches" do
        subject.groups(/back$/).should eql []
      end
    end
  end

  describe ".reset_groups" do
    subject do
      guard = ::Guard.setup
      @group_backend  = guard.add_group(:backend)
      @group_backflip = guard.add_group(:backflip)
      guard
    end

    it "return @groups without any argument" do
      subject.groups.should have(4).items

      subject.reset_groups

      subject.groups.should have(1).item
      subject.groups[0].name.should eql :default
      subject.groups[0].options.should == {}
    end
  end

  describe ".start" do
    let(:options) { { :my_opts => true, :guardfile => File.join(@fixture_path, "Guardfile") } }

    before do
      Guard.stub(:setup)
      Guard.listener.stub(:start)
      Guard::Dsl.stub(:evaluate_guardfile)
      Guard::Notifier.stub(:turn_on)
      Guard::Notifier.stub(:turn_off)
    end

    it "setup Guard" do
      ::Guard.should_receive(:setup).with(options)
      ::Guard.start(options)
    end

    it "starts the listeners" do
      ::Guard.listener.should_receive(:start)
      ::Guard.start(options)
    end
  end

  describe ".add_guard" do
    before(:each) do
      @guard_rspec_class = double('Guard::RSpec')
      @guard_rspec = double('Guard::RSpec')

      Guard.stub!(:get_guard_class) { @guard_rspec_class }

      Guard.guards = []
    end

    it "accepts guard name as string" do
      @guard_rspec_class.should_receive(:new).and_return(@guard_rspec)

      Guard.add_guard('rspec')
    end

    it "accepts guard name as symbol" do
      @guard_rspec_class.should_receive(:new).and_return(@guard_rspec)

      Guard.add_guard(:rspec)
    end

    it "adds guard to the @guards array" do
      @guard_rspec_class.should_receive(:new).and_return(@guard_rspec)

      Guard.add_guard(:rspec)

      Guard.guards.should eql [@guard_rspec]
    end

    context "with no watchers given" do
      it "gives an empty array of watchers" do
        @guard_rspec_class.should_receive(:new).with([], {}).and_return(@guard_rspec)

        Guard.add_guard(:rspec, [])
      end
    end

    context "with watchers given" do
      it "give the watchers array" do
        @guard_rspec_class.should_receive(:new).with([:foo], {}).and_return(@guard_rspec)

        Guard.add_guard(:rspec, [:foo])
      end
    end

    context "with no options given" do
      it "gives an empty hash of options" do
        @guard_rspec_class.should_receive(:new).with([], {}).and_return(@guard_rspec)

        Guard.add_guard(:rspec, [], [], {})
      end
    end

    context "with options given" do
      it "give the options hash" do
        @guard_rspec_class.should_receive(:new).with([], { :foo => true, :group => :backend }).and_return(@guard_rspec)

        Guard.add_guard(:rspec, [], [], { :foo => true, :group => :backend })
      end
    end
  end

  describe ".add_group" do
     before { ::Guard.reset_groups }
     subject { ::Guard }

    it "accepts group name as string" do
      subject.add_group('backend')

      subject.groups[0].name.should eql :default
      subject.groups[1].name.should eql :backend
    end

    it "accepts group name as symbol" do
      subject.add_group(:backend)

      subject.groups[0].name.should eql :default
      subject.groups[1].name.should eql :backend
    end

    it "accepts options" do
      subject.add_group(:backend, { :halt_on_fail => true })

      subject.groups[0].options.should eq({})
      subject.groups[1].options.should eq({ :halt_on_fail => true })
    end
  end

  describe '.within_preserved_state' do
    subject { ::Guard.setup }

    it 'disables the interactor before running the block and then re-enables it when done' do
      subject.interactor.should_receive(:stop)
      subject.interactor.should_receive(:start)
      subject.within_preserved_state &Proc.new {}
    end

    it 'disallows running the block concurrently to avoid inconsistent states' do
      subject.lock.should_receive(:synchronize)
      subject.within_preserved_state &Proc.new {}
    end

    it 'runs the passed block' do
      @called = false
      subject.within_preserved_state { @called = true }
      @called.should be_true
    end
  end

  describe ".get_guard_class" do
    after do
      [:Classname, :DashedClassName, :UnderscoreClassName, :VSpec, :Inline].each do |const|
        Guard.send(:remove_const, const) rescue nil
      end
    end

    it "reports an error if the class is not found" do
      ::Guard::UI.should_receive(:error).twice
      Guard.get_guard_class('notAGuardClass')
    end

    context 'with a nested Guard class' do
      after(:all) { Guard.instance_eval { remove_const(:Classname) } rescue nil }

      it "resolves the Guard class from string" do
        Guard.should_receive(:require) { |classname|
          classname.should eq 'guard/classname'
          class Guard::Classname; end
        }
        Guard.get_guard_class('classname').should == Guard::Classname
      end

      it "resolves the Guard class from symbol" do
        Guard.should_receive(:require) { |classname|
          classname.should eq 'guard/classname'
          class Guard::Classname; end
        }
        Guard.get_guard_class(:classname).should == Guard::Classname
      end
    end

    context 'with a name with dashes' do
      after(:all) { Guard.instance_eval { remove_const(:DashedClassName) } rescue nil }

      it "returns the Guard class" do
        Guard.should_receive(:require) { |classname|
          classname.should eq 'guard/dashed-class-name'
          class Guard::DashedClassName; end
        }
        Guard.get_guard_class('dashed-class-name').should == Guard::DashedClassName
      end
    end

    context 'with a name with underscores' do
      after(:all) { Guard.instance_eval { remove_const(:UnderscoreClassName) } rescue nil }

      it "returns the Guard class" do
        Guard.should_receive(:require) { |classname|
          classname.should eq 'guard/underscore_class_name'
          class Guard::UnderscoreClassName; end
        }
        Guard.get_guard_class('underscore_class_name').should == Guard::UnderscoreClassName
      end
    end

    context 'with a name where its class does not follow the strict case rules' do
      after(:all) { Guard.instance_eval { remove_const(:VSpec) } rescue nil }

      it "returns the Guard class" do
        Guard.should_receive(:require) { |classname|
          classname.should eq 'guard/vspec'
          class Guard::VSpec; end
        }
        Guard.get_guard_class('vspec').should == Guard::VSpec
      end
    end

    context 'with an inline Guard class' do
      after(:all) { Guard.instance_eval { remove_const(:Inline) } rescue nil }

      it 'returns the Guard class' do
        module Guard
          class Inline < Guard
          end
        end

        Guard.should_not_receive(:require)
        Guard.get_guard_class('inline').should == Guard::Inline
      end
    end

    context 'when set to fail gracefully' do
      it 'does not print error messages on fail' do
        ::Guard::UI.should_not_receive(:error)
        Guard.get_guard_class('notAGuardClass', true).should be_nil
      end
    end
  end

  describe ".locate_guard" do
    it "returns the path of a Guard gem" do
      if Gem::Version.create(Gem::VERSION) >= Gem::Version.create('1.8.0')
        gem_location = Gem::Specification.find_by_name("guard-rspec").full_gem_path
      else
        gem_location = Gem.source_index.find_name("guard-rspec").last.full_gem_path
      end

      Guard.locate_guard('rspec').should == gem_location
    end
  end

  describe ".guard_gem_names" do
    it "returns the list of guard gems" do
      gems = Guard.guard_gem_names
      gems.should include("rspec")
    end
  end

  describe ".debug_command_execution" do
    subject { ::Guard.setup }

    before do
      @original_system = Kernel.method(:system)
      @original_command = Kernel.method(:"`")
    end

    after do
      Kernel.send(:remove_method, :system, :'`')
      Kernel.send(:define_method, :system, @original_system.to_proc)
      Kernel.send(:define_method, :"`", @original_command.to_proc)
    end

    it "outputs Kernel.#system method parameters" do
      ::Guard.setup(:verbose => true)
      ::Guard::UI.should_receive(:debug).with("Command execution: exit 0")
      system("exit", "0").should be_false
    end

    it "outputs Kernel.#` method parameters" do
      ::Guard.setup(:verbose => true)
      ::Guard::UI.should_receive(:debug).twice.with("Command execution: echo test")
      `echo test`.should eql "test\n"
      %x{echo test}.should eql "test\n"
    end

  end

end
