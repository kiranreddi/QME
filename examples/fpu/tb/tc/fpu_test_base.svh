import mti_fli::*;

class fpu_test_base extends uvm_test;

int verbosity_level = UVM_MEDIUM;
int m_logfile_handle;
      
`uvm_component_utils(fpu_test_base)

  
   fpu_agent_config m_fpu_master_agent_config;
   fpu_agent_config m_fpu_slave_agent_config;

	fpu_env_config m_cfg;  
	fpu_environment m_env;

	// Handle to sequencer down in the test environment
	uvm_sequencer #(fpu_item, fpu_item) seqr_handle;
 

	function new(string name = "fpu_test_base", uvm_component parent=null);
      super.new(name, parent);
	endfunction // new


	function string send2vsim(string cmd = "" );
      string result;
      chandle interp;

      interp = mti_Interp();
      uvm_report_info( get_type_name(), $psprintf( "Sending \"%s\" to Questa", cmd), UVM_FULL ); 
      assert (! mti_Cmd(cmd));
      result = Tcl_GetStringResult(interp);
      Tcl_ResetResult(interp);
      uvm_report_info( get_type_name(), $psprintf( "Received \"%s\" from Questa", result), UVM_FULL );       
      return result;
	endfunction


	function void build_phase(uvm_phase phase); 
      string result;
      string verbosity_level_s;
		
      if ( $value$plusargs("UVM_VERBOSITY_LEVEL=%s",verbosity_level_s)) begin
          case (verbosity_level_s)
          "UVM_NONE"   : verbosity_level = UVM_NONE;
          "UVM_LOW"    : verbosity_level = UVM_LOW;
          "UVM_MEDIUM" : verbosity_level = UVM_MEDIUM;
          "UVM_HIGH"   : verbosity_level = UVM_HIGH;
          "UVM_FULL"   : verbosity_level = UVM_FULL;
          "UVM_DEBUG"  : verbosity_level = UVM_DEBUG;
          default: verbosity_level = UVM_MEDIUM;
          endcase // case(verbosity_level_s)
      end 
      else begin
        verbosity_level = UVM_MEDIUM;
      end
      
      uvm_report_info( get_type_name(), $psprintf("Setting verbosity_level: %0d", verbosity_level), UVM_FULL );
      uvm_config_db#(int)::set(this,"","verbosity_level", verbosity_level);

      m_rh.set_verbosity_level(verbosity_level);
      set_report_verbosity_level_hier(verbosity_level); // default

      // log to display (std out) and file
      set_report_severity_action(UVM_INFO, UVM_DISPLAY | UVM_LOG);
      set_report_severity_action(UVM_ERROR,   UVM_DISPLAY | UVM_LOG | UVM_COUNT );
      set_report_severity_action(UVM_FATAL,   UVM_DISPLAY | UVM_LOG | UVM_EXIT );

      super.build_phase(phase);
      
      //Using the uvm 2.0 factory 
      m_env = fpu_environment::type_id::create("m_env", this);

		m_fpu_master_agent_config = fpu_agent_config::type_id::create("m_fpu_master_agent_config");
		m_fpu_master_agent_config.m_agent_mode      = RTL_MASTER;
		m_fpu_master_agent_config.m_tlm_timing_mode = LT_MODE;
		m_fpu_master_agent_config.m_socket_type  = INITIATOR_SOCKET; 
		m_fpu_master_agent_config.sc_lookup_name = "request_socket";   

		m_fpu_slave_agent_config = fpu_agent_config::type_id::create("m_fpu_slave_agent_config");
		m_fpu_slave_agent_config.m_agent_mode      = RTL_SLAVE;
		m_fpu_slave_agent_config.m_tlm_timing_mode = LT_MODE;
		m_fpu_slave_agent_config.m_socket_type  = TARGET_SOCKET; 
		m_fpu_slave_agent_config.sc_lookup_name = "response_socket";   
		
		m_cfg = fpu_env_config::type_id::create("m_cfg",this);
		m_cfg.m_fpu_master_agent_config = m_fpu_master_agent_config;
		m_cfg.m_fpu_slave_agent_config  = m_fpu_slave_agent_config;
	
		uvm_config_db #(fpu_env_config)::set(this,"*","fpu_env_config",m_cfg);
		uvm_config_db #(fpu_agent_config)::set(this,"*master*","fpu_agent_config",m_fpu_master_agent_config);
		uvm_config_db #(fpu_agent_config)::set(this,"*slave*","fpu_agent_config",m_fpu_slave_agent_config);

      uvm_report_info( get_type_name(), $psprintf("Master random number generator seeded with: %0d", get_seed()), UVM_LOW );

      // Set the name of the sequencer
      uvm_config_db#(string)::set(this,"m_env.*","SEQR_NAME", "main_sequencer");

	endfunction


	virtual function void end_of_elaboration_phase(uvm_phase phase); 
      if (verbosity_level == UVM_FULL) begin
         print_config();
      end

      if (verbosity_level == UVM_HIGH) begin
         uvm_top.print_topology();
      end

      //find the sequencer in the testbench
      assert($cast(seqr_handle, uvm_top.find("*main_sequencer")));  
	endfunction // end_of_elaboration


	virtual task run_phase(uvm_phase phase); 
      //int runtime = $urandom_range(2,6)*1000;
      int runtime = `TIMEOUT;
		phase.raise_objection(this,"run_phase raise objection in fpu_test_base");
      
      uvm_report_info(get_type_name(), "No Sequences started ...", UVM_LOW); 
      #runtime;
      uvm_report_info(get_type_name(), "Stopping test...", UVM_LOW );      
		phase.drop_objection(this,"run_phase drop objection in fpu_test_base");
	endtask


	function int get_seed();
      string result;
      result = send2vsim("lindex $Sv_Seed 0");
      return result.atoi();
	endfunction


	function int get_teststatus();
      string cmd = "lindex [coverage attr -name TESTSTATUS -concise] 0";
      string result, msg;

      result = send2vsim(cmd);
      // OK = "0", Warning = "1", Error = "2", or Fatal ="3"
      $sformat(msg, "vsim reported %0d as the teststatus", result);
      uvm_report_info( get_type_name(), msg, UVM_FULL ); 
      return result.atoi();
	endfunction

      
	virtual function void report_phase(uvm_phase phase);     // report
      string cmd,msg, result;
      uvm_report_server rs; 
      
      int fatal_count;
      int error_count;
      int warning_count;
      int message_count;

      int teststatus;
      //rs = m_rh.m_glob.get_server();
      phase.raise_objection(this,"report_phase in fpu_test_base raise objection");
      rs = m_rh.get_server();

      fatal_count = rs.get_severity_count(UVM_FATAL);
      error_count = rs.get_severity_count(UVM_ERROR);
      warning_count = rs.get_severity_count(UVM_WARNING);
      message_count = rs.get_severity_count(UVM_INFO);

      teststatus = get_teststatus();
      
      super.report_phase(phase);
      
//      Results_for_testcase: assert ( (warning_count==0) && (error_count==0) && (fatal_count==0) && ( teststatus==0 || teststatus==1) )  
      Results_for_testcase: assert ( (error_count==0) && (fatal_count==0) && ( teststatus==0 || teststatus==1) )  
      begin
         if (teststatus == 0) 
           uvm_report_info( get_type_name(),$psprintf("Test Results: Passed with no errors"), UVM_LOW);
         else
           uvm_report_info( get_type_name(),$psprintf("Test Results: Passed with no errors but with DUT warning(s)"), UVM_LOW);
      end
      else begin
         $sformat(msg, "Test Results: Failed with %0d error(s)", error_count);
         uvm_report_error( get_type_name(), msg, UVM_LOW,`__FILE__,`__LINE__);
         $error(""); // signal to vsim
      end
      phase.drop_objection(this,"report_phase in fpu_test_base drop objection");

	endfunction // void

endclass
