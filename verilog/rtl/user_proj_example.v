// SPDX-FileCopyrightText: 2020 Efabless Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// SPDX-License-Identifier: Apache-2.0

`default_nettype none
/*
 *-------------------------------------------------------------
 *
 * user_proj_example
 *
 * This is an example of a (trivially simple) user project,
 * showing how the user project can connect to the logic
 * analyzer, the wishbone bus, and the I/O pads.
 *
 * This project generates an integer count, which is output
 * on the user area GPIO pads (digital output only).  The
 * wishbone connection allows the project to be controlled
 * (start and stop) from the management SoC program.
 *
 * See the testbenches in directory "mprj_counter" for the
 * example programs that drive this user project.  The three
 * testbenches are "io_ports", "la_test1", and "la_test2".
 *
 *-------------------------------------------------------------
 */

`define MAX_SOC 1
`define BUS_WIDTH 16 
module user_proj_example #(
    parameter BITS = 32
)(
`ifdef USE_POWER_PINS
    inout vccd1,	// User area 1 1.8V supply
    inout vssd1,	// User area 1 digital ground
`endif

    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [3:0] wbs_sel_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output wbs_ack_o,
    output [31:0] wbs_dat_o,

    // Logic Analyzer Signals
    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,

    // IOs
    input  [`MPRJ_IO_PADS-1:0] io_in,
    output [`MPRJ_IO_PADS-1:0] io_out,
    output [`MPRJ_IO_PADS-1:0] io_oeb,

    // IRQ
    output [2:0] irq
);


  localparam  STATUS_ADDR	    =  'd0; 
  localparam  PRE_ADDR 			=  'd1; 

  reg [2*`BUS_WIDTH-1:0] status;
  reg [2*`BUS_WIDTH-1:0] rdata;
  reg [2*`BUS_WIDTH-1:0]  prescaler;
  reg  wbs_done;
  wire wb_valid;
  wire [3:0] wstrb;


  wire  [`MAX_SOC-1:0] cmp;
  wire mclear;
  wire mclk;
  wire ce_pcm;
  wire ce_pdm;
  wire addr_valid;


  reg [`MAX_SOC-1:0] valid_i;
  wire  strb_i;
  wire [3:0] adr_i;
  wire [`BUS_WIDTH-1:0] dat_i;
  wire [10:0]  addr;
  
  wire [`BUS_WIDTH-1:0] dat_o[`MAX_SOC];
  wire                  ack_o[`MAX_SOC];

  reg [`BUS_WIDTH-1:0] wbs_dat;
  reg wbs_ack;


  assign dat_i = {wbs_dat_i[31], wbs_dat_i[14:0]};
  assign addr = ((wbs_adr_i[11:0] >> 2) - 11'd2);
  assign adr_i = addr[3:0];
  assign strb_i = wstrb[0];


  assign wb_valid = wbs_cyc_i && wbs_stb_i; 
  assign wstrb = wbs_sel_i & {4{wbs_we_i}};
  assign addr_valid = (wbs_adr_i[31:28] == 3) ? 1 : 0;
 
  assign irq[0] = ((|status) | (|prescaler[25:24]) );
  /*clear send from CARAVEL*/
  assign mclear  = la_data_in[0];
  /*  assign 4.5 MHz clock on GPIO0*/
  assign io_out[0] = mclk;
  assign io_oeb[0] = 1'b0;
  
  assign io_oeb[1] = 1'b1;
 


  always@(addr  or wb_valid or addr_valid) begin

	if (wb_valid && addr_valid)  begin  
        case(addr[10:4])   
				 'd0 :  begin  valid_i[0]  <= 1'b1; end  
                  default: begin valid_i <= 0 ;  end
		endcase
    end
    else 
      valid_i <= 0;
  end



  always@(valid_i   or dat_o[0] or ack_o[0] ) begin
        case(valid_i)   
				 'h1     :  begin 
							wbs_dat <=  dat_o[0];
							wbs_ack <=  ack_o[0];
                            end
                  default: begin 
							wbs_dat <=  0;
							wbs_ack <=  0;
                           end
		endcase
  end

assign wbs_dat_o =   (valid_i != 0)  ? {{16{wbs_dat[15]}},wbs_dat} : rdata;
assign wbs_ack_o =   (valid_i != 0)  ? wbs_ack                     : wbs_done;




	always@(posedge wb_clk_i) begin
		if(wb_rst_i) begin
			wbs_done  <= 0;
			status    <= 0;
			prescaler <= 49;
            rdata     <= 0;
		end
		else begin
			wbs_done <= 0;
			if (wb_valid && addr_valid)  begin     
				case(wbs_adr_i[7:2])   
					STATUS_ADDR: 
 						begin	
                   	    	rdata <= status;
						end            
					PRE_ADDR:
 						begin	
                   	        rdata <= prescaler;
                   		if(strb_i)
       						prescaler[9:0] <= wbs_dat_i[9:0];
                        end
                  default: ;
				endcase
 			 wbs_done <= 1; 
			end
            else begin
 		    end        
        end
   end 


/*  write status register */
	always@(posedge wb_clk_i) begin
		if(wb_rst_i) begin
			status  <= 0;
		end 
        else 
          status <= cmp;
         // prescaler[25:24] <= cmp[33:32];
       
    end


/*  ----------------------  STRUCTURAL DESIGN BEGINS ----------------------- */

micclk  mic(
        .clk(wb_clk_i),
        .rst(wb_rst_i),
        .mclk(mclk),
        .ce_pdm(ce_pdm)
        );

pcm_clk  pcmclk(
        .clk(wb_clk_i),
        .rst(wb_rst_i),
        .prescaler(prescaler[9:0]),
        .ce_pcm(ce_pcm)
        );
 

SonarOnChip   soc1(

    .wb_clk_i(wb_clk_i),
    .wb_rst_i(wb_rst_i),
    .wb_valid_i(valid_i[0]),
    .wbs_adr_i(adr_i),
    .wbs_dat_i(dat_i),
    .wbs_strb_i(strb_i),
    .wbs_ack_o(ack_o[0]),
    .wbs_dat_o(dat_o[0]),
    
    .ce_pdm(ce_pdm),
    .ce_pcm(ce_pcm),
    .pdm_data_i(io_in[1]),
    .mclear(mclear),
    .cmp(cmp[0])
	);

endmodule
`default_nettype wire
