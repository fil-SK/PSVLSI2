
`include "uvm_macros.svh"
import uvm_pkg::*;


// 2. Sequence Item
class ps2_item extends uvm_sequence_item;

    rand bit [10:0] ps2_data;

    bit [21:0] display_data;
    bit flag;

    bit [10:0] driver_data;

    //constraint start_bit    { ( ps2_data[0]  inside { 1'b0 } ); }
    //constraint stop_bit     { ( ps2_data[10] inside { 1'b1 } ); }



    `uvm_object_utils_begin(ps2_item)
		`uvm_field_int(ps2_data, UVM_DEFAULT)
		`uvm_field_int(display_data, UVM_DEFAULT)
	`uvm_object_utils_end


    function new(string name = "ps2_item");
		super.new(name);
	endfunction


    virtual function string my_print();
		return $sformatf(
            "display_data = %22b", display_data
		);
	endfunction
endclass


// 3. Sequence
class generator extends uvm_sequence;

    `uvm_object_utils(generator)

    function new(string name = "generator");
		super.new(name);
	endfunction




    // Sa 1000 iteracija desavalo nam se da se na levoj strani nadje F0 i E0 i radi ispravno
    // Stavis 1000 iteracija da proveris da ti levo stavlja E0 i F0
    // Sa manje iteracija to obicno nece da se desi
    int num = 100;
    
    bit parity_bit = 1'b0;      // Namestamo parity


    virtual task body();

        // 
        for (int i = 0; i < num; i++) begin
            ps2_item item = ps2_item::type_id::create("item");

            start_item(item);
            item.randomize();


            // Ovo promenim da bi proverio da li prolazi test za start i stop ili ne
            // Kako bi se modul ponasao ispravno potrebno je da se hardkoduju start=0 i stop=1, ali za testiranje provere ispravnosti ovih bitova njih je potrebno menjati
            item.ps2_data[0] = 1'b0;            // start bit postavljamo eksplicitno na 0 da bi radilo lepo (jer modul nece krenuti osim ako mu ne dodje 0 - po protokolu)
            item.ps2_data[10] = 1'b1;           // end bit postavljamo eksplicitno na 1


            /*  TODO
                Blok koda kad postavljamo F0 nesto
                item.ps2_data[10:0] = 11' F0;
            */


            // Namestamo da je parity ispravan
            parity_bit = item.ps2_data[1] ^ item.ps2_data[2] ^ item.ps2_data[3] ^ item.ps2_data[4] ^ item.ps2_data[5] ^ item.ps2_data[6] ^ item.ps2_data[7] ^ item.ps2_data[8];
            if(parity_bit == 1'b1) begin
                item.ps2_data[9] = 1'b0;
            end
            else begin
                item.ps2_data[9] = 1'b1;
            end


            item.driver_data = item.ps2_data;


            `uvm_info("Generator", $sformatf("Item %0d/%0d created", i + 1, num), UVM_LOW)
            `uvm_info("Generator", $sformatf("Random broj je %0d/%11b created", i + 1, item.ps2_data), UVM_LOW)

            item.print();

            finish_item(item);
        end

	endtask

endclass



// 4. Driver
class driver extends uvm_driver #(ps2_item);

    `uvm_component_utils(driver)


    function new(string name = "driver", uvm_component parent = null);
		super.new(name, parent);
	endfunction


    virtual ps2_if vif;


    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual ps2_if)::get(this, "", "ps2_vif", vif))
            `uvm_fatal("Driver", "No interface.")
    endfunction


    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);

        forever begin
            ps2_item item;
            seq_item_port.get_next_item(item);
            `uvm_info("Driver", $sformatf("%s", item.my_print()), UVM_LOW)
            `uvm_info("Driver", $sformatf("ps2_data = %11b", item.ps2_data), UVM_LOW)


            for(int i = 0; i < 11; i++) begin
                @(posedge vif.ps2_clk);
                vif.ps2_data <= item.ps2_data[i];
                vif.driver_data[i] <= item.driver_data[i];         // ovde smo sacuvali vrednosti koje je driver ubacio
            end


            seq_item_port.item_done();
        end
    endtask
endclass



// 5. Monitor
class monitor extends uvm_monitor;

    `uvm_component_utils(monitor)

    function new(string name = "monitor", uvm_component parent = null);
		super.new(name, parent);
	endfunction


    virtual ps2_if vif;
    uvm_analysis_port #(ps2_item) mon_analysis_port;


    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual ps2_if)::get(this, "", "ps2_vif", vif))
            `uvm_fatal("Monitor", "No interface.")
        mon_analysis_port = new("mon_analysis_port", this);
    endfunction


    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        @(posedge vif.clk);

        forever begin

            ps2_item item = ps2_item::type_id::create("item");
            
            @(posedge vif.flag);                                  // DODATO!!!
            item.display_data = vif.display_data;
            item.driver_data = vif.driver_data;                   // ucitali smo ulazne podatke koje je driver slao na ulaz za ovaj izlazni display_data
            
                

            `uvm_info("Monitor", $sformatf("%s", item.my_print()), UVM_LOW)

            mon_analysis_port.write(item);
        end
    endtask
endclass



// 6. Agent
class agent extends uvm_agent;

    `uvm_component_utils(agent)

    function new(string name = "agent", uvm_component parent = null);
		super.new(name, parent);
	endfunction


    driver d0;
	monitor m0;
	uvm_sequencer #(ps2_item) s0;


    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        d0 = driver::type_id::create("d0", this);
		m0 = monitor::type_id::create("m0", this);
		s0 = uvm_sequencer#(ps2_item)::type_id::create("s0", this);
    endfunction


    virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		d0.seq_item_port.connect(s0.seq_item_export);
	endfunction

endclass



// 7. Scoreboard
class scoreboard extends uvm_scoreboard;

    `uvm_component_utils(scoreboard)

    function new(string name = "scoreboard", uvm_component parent = null);
		super.new(name, parent);
	endfunction


    uvm_analysis_imp #(ps2_item, scoreboard) mon_analysis_imp;


    virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		mon_analysis_imp = new("mon_analysis_imp", this);
	endfunction



    bit [21:0] display_data = 22'd0;
    bit packet_received = 1'b0;

    virtual function write(ps2_item item);




    // TODO : Parity, Start, Stop, Frame Check

    // item.driver_data         podaci koje smo slali na driver
    // item.display_data        podaci koje dohvatamo iz monitora
    // display_data             nas output koji generisemo iz testbencha

    // Pakovanje vrednosti u 22 bita za display_data
    if( (item.driver_data[8:1] != 8'hF0 && item.driver_data[8:1] != 8'hE0) ) begin
                    
        if(display_data[19:12] == 8'h00) begin
            display_data[21:11] = 11'd0;
            display_data[10:0] = item.driver_data;     // Primili desnu stranu

            `uvm_info("Scoreboard write", $sformatf("Display data =  %22b", display_data), UVM_LOW)

            // Parity check
            if(item.display_data[1] ^ item.display_data[2] ^ item.display_data[3] ^ item.display_data[4] ^ item.display_data[5] ^ item.display_data[6] ^ item.display_data[7] ^ item.display_data[8] ^ item.display_data[9] == 1'b1) begin
                    `uvm_info("Scoreboard", $sformatf("PARITY PASS!"), UVM_LOW)
            end
            else begin
                `uvm_error("Scoreboard", $sformatf("PARITY FAIL!"))
            end

            // Start check
            if(item.display_data[0] == 1'b0) begin
                `uvm_info("Scoreboard", $sformatf("START PASS!"), UVM_LOW)
            end
            else begin
                `uvm_error("Scoreboard", $sformatf("START FAIL!"))
            end

            // Stop check
            if(item.display_data[10] == 1'b1) begin
                `uvm_info("Scoreboard", $sformatf("STOP PASS!"), UVM_LOW)
            end
            else begin
                `uvm_error("Scoreboard", $sformatf("STOP FAIL!"))
            end

        end


        else if(display_data[19:12] == 8'hF0) begin

            if(packet_received == 1'b1) begin
                display_data[21:11] = 11'd0;
                display_data[10:0] = item.driver_data;
                packet_received = 1'b0;         // Resetujemo zbog primanja novog paketa



                // Parity check
                if(item.display_data[1] ^ item.display_data[2] ^ item.display_data[3] ^ item.display_data[4]
                    ^ item.display_data[5] ^ item.display_data[6] ^ item.display_data[7] ^ item.display_data[8] ^ item.display_data[9] == 1'b1) begin
                        `uvm_info("Scoreboard", $sformatf("PARITY PASS!"), UVM_LOW)
                    end
                else begin
                    `uvm_error("Scoreboard", $sformatf("PARITY FAIL!"))
                end

                // Start check
                if(item.display_data[0] == 1'b0) begin
                    `uvm_info("Scoreboard", $sformatf("START PASS!"), UVM_LOW)
                end
                else begin
                    `uvm_error("Scoreboard", $sformatf("START FAIL!"))
                end

                // Stop check
                if(item.display_data[10] == 1'b1) begin
                    `uvm_info("Scoreboard", $sformatf("STOP PASS!"), UVM_LOW)
                end
                else begin
                    `uvm_error("Scoreboard", $sformatf("STOP FAIL!"))
                end


            end

            else begin      // Ako je packet_received = 0 (radi se za F0)
                // display_data[21:11] = left_reg;       // Zadrzavamo stari left reg tj. F0 vrednost
                display_data[10:0] = item.driver_data;
                packet_received = 1'b1;                 // Primili smo ceo paket



                    // Parity check
                    if(item.display_data[1] ^ item.display_data[2] ^ item.display_data[3] ^ item.display_data[4]
                        ^ item.display_data[5] ^ item.display_data[6] ^ item.display_data[7] ^ item.display_data[8] ^ item.display_data[9] == 1'b1) begin
                            `uvm_info("Scoreboard", $sformatf("PARITY PASS!"), UVM_LOW)
                        end
                    else begin
                        `uvm_error("Scoreboard", $sformatf("PARITY FAIL!"))
                    end

                    // Start check
                    if(item.display_data[0] == 1'b0) begin
                        `uvm_info("Scoreboard", $sformatf("START PASS!"), UVM_LOW)
                    end
                    else begin
                        `uvm_error("Scoreboard", $sformatf("START FAIL!"))
                    end

                    // Stop check
                    if(item.display_data[10] == 1'b1) begin
                        `uvm_info("Scoreboard", $sformatf("STOP PASS!"), UVM_LOW)
                    end
                    else begin
                        `uvm_error("Scoreboard", $sformatf("STOP FAIL!"))
                    end

                end
        end

        else if(display_data[19:12] == 8'hE0) begin
            // display_data[19:12] = left_reg;           // Zadrzavamo stari left reg tj. E0 vrednost
            display_data[10:0] = item.driver_data;


                // Parity check
                if(item.display_data[1] ^ item.display_data[2] ^ item.display_data[3] ^ item.display_data[4]
                    ^ item.display_data[5] ^ item.display_data[6] ^ item.display_data[7] ^ item.display_data[8] ^ item.display_data[9] == 1'b1) begin
                        `uvm_info("Scoreboard", $sformatf("PARITY PASS!"), UVM_LOW)
                    end
                else begin
                    `uvm_error("Scoreboard", $sformatf("PARITY FAIL!"))
                end

                // Start check
                if(item.display_data[0] == 1'b0) begin
                    `uvm_info("Scoreboard", $sformatf("START PASS!"), UVM_LOW)
                end
                else begin
                    `uvm_error("Scoreboard", $sformatf("START FAIL!"))
                end

                // Stop check
                if(item.display_data[10] == 1'b1) begin
                    `uvm_info("Scoreboard", $sformatf("STOP PASS!"), UVM_LOW)
                end
                else begin
                    `uvm_error("Scoreboard", $sformatf("STOP FAIL!"))
                end
           
        end

    end






    // Stize F0 i to ide levo

    else if( item.driver_data[8:1] == 8'hF0 ) begin
        display_data[21:11] = item.driver_data;// stavi F0 u levi
        // desni ne stavljamo jer je ostalo od prethodno pritisnutog desnog
        packet_received = 1'b0;            // Primamo levu stranu pa paket jos uvek nije stigao ceo



            // Parity check
            if(item.display_data[12] ^ item.display_data[13] ^ item.display_data[14] ^ item.display_data[15]
                ^ item.display_data[16] ^ item.display_data[17] ^ item.display_data[18] ^ item.display_data[19] ^ item.display_data[20] == 1'b1) begin
                    `uvm_info("Scoreboard", $sformatf("PARITY PASS!"), UVM_LOW)
                end
            else begin
                `uvm_error("Scoreboard", $sformatf("PARITY FAIL!"))
            end

            // Start check
            if(item.display_data[11] == 1'b0) begin
                `uvm_info("Scoreboard", $sformatf("START PASS!"), UVM_LOW)
            end
            else begin
                `uvm_error("Scoreboard", $sformatf("START FAIL!"))
            end

            // Stop check
            if(item.display_data[21] == 1'b1) begin
                `uvm_info("Scoreboard", $sformatf("STOP PASS!"), UVM_LOW)
            end
            else begin
                `uvm_error("Scoreboard", $sformatf("STOP FAIL!"))
            end


    end




    // Stize E0 i to ide levo

    else if( item.driver_data[8:1] == 8'hE0 ) begin
        display_data[21:11] = item.driver_data;
        // desni ne stavljamo jer je ostalo od prethodno pritisnutog desnog
        packet_received = 1'b0;            // Primamo levu stranu pa paket jos uvek nije stigao ceo


            // Parity check
            if(item.display_data[12] ^ item.display_data[13] ^ item.display_data[14] ^ item.display_data[15]
                ^ item.display_data[16] ^ item.display_data[17] ^ item.display_data[18] ^ item.display_data[19] ^ item.display_data[20] == 1'b1) begin
                    `uvm_info("Scoreboard", $sformatf("PARITY PASS!"), UVM_LOW)
                end
            else begin
                `uvm_error("Scoreboard", $sformatf("PARITY FAIL!"))
            end

            // Start check
            if(item.display_data[11] == 1'b0) begin
                `uvm_info("Scoreboard", $sformatf("START PASS!"), UVM_LOW)
            end
            else begin
                `uvm_error("Scoreboard", $sformatf("START FAIL!"))
            end

            // Stop check
            if(item.display_data[21] == 1'b1) begin
                `uvm_info("Scoreboard", $sformatf("STOP PASS!"), UVM_LOW)
            end
            else begin
                `uvm_error("Scoreboard", $sformatf("STOP FAIL!"))
            end


    end


    if (display_data == item.display_data)
		`uvm_info("Scoreboard", $sformatf("PASS!"), UVM_LOW)
	else
		`uvm_error("Scoreboard", $sformatf("FAIL! expected = %22b, got = %22b", display_data, item.display_data))


    endfunction

endclass




// 8. Environment
class env extends uvm_env;
    `uvm_component_utils(env)


    function new(string name = "env", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	

	agent a0;
	scoreboard sb0;


    virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		a0 = agent::type_id::create("a0", this);
		sb0 = scoreboard::type_id::create("sb0", this);
	endfunction


    virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		a0.m0.mon_analysis_port.connect(sb0.mon_analysis_imp);
	endfunction

endclass



// 9. Test
class test extends uvm_test;

    `uvm_component_utils(test)

    function new(string name = "test", uvm_component parent = null);
		super.new(name, parent);
	endfunction


    virtual ps2_if vif;

    env e0;
	generator g0;


    virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if (!uvm_config_db#(virtual ps2_if)::get(this, "", "ps2_vif", vif))
			`uvm_fatal("Test", "No interface.")
		e0 = env::type_id::create("e0", this);
		g0 = generator::type_id::create("g0");
	endfunction


    virtual function void end_of_elaboration_phase(uvm_phase phase);
		uvm_top.print_topology();
	endfunction


    virtual task run_phase(uvm_phase phase);
		phase.raise_objection(this);
		
		vif.rst_n <= 0;
		#20 vif.rst_n <= 1;			// Postavljamo reset
		
		g0.start(e0.a0.s0);			// Pokrecemo generator
		phase.drop_objection(this);
	endtask

endclass



// 1. Interface

interface ps2_if (
    input bit clk,
    input bit ps2_clk
);

    logic rst_n;
    logic ps2_data;
    logic [21:0] display_data;
    logic flag;

    logic [10:0] driver_data;               // Da bismo u scoreboardu mogli da uzimamo ono sto smo slali na drajver

endinterface




// 10. FINAL BOSS
module testbench;

    reg clk;
    reg ps2_clk;

    ps2_if dut_if (
		.clk(clk),
        .ps2_clk(ps2_clk)
	);


    ps2 dut(
        .clk(clk),
        .ps2_clk(ps2_clk),
        .rst_n(dut_if.rst_n),
        .ps2_data(dut_if.ps2_data),
        .display_data(dut_if.display_data),
        .flag(dut_if.flag)
    );


    initial begin
		clk = 0;
		forever begin
            // MENJALI CLK
			#10 clk = ~clk;
		end
	end

    initial begin
        ps2_clk = 0;
        forever begin
            // MENJALI CLK
            #40_000 ps2_clk = ~ps2_clk;
        end
    end


    initial begin
		uvm_config_db#(virtual ps2_if)::set(null, "*", "ps2_vif", dut_if);
		run_test("test");
	end



endmodule
