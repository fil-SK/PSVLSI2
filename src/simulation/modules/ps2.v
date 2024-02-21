module ps2(
    input clk,
    input rst_n,
    input ps2_clk,                          // Prima se debounce-ovan signal kloka tastature
    input ps2_data,
    output [21:0] display_data,
    output wire flag
);

    // Stanja za Finite State Machine
    localparam initial_state = 2'b00;
    localparam read_state = 2'b01;
    localparam display_state = 2'b10;


    // Pomocne promenljive
    reg [1:0] state_reg, state_next;
    reg [3:0] counter_reg, counter_next;        // Broji do kog smo bita ucitali

    wire neg_edge;

    reg [10:0] data_reg, data_next;             // Sacuvanih 11 bita iz paketa

    // Vrednosti za out za displej - data samo
    reg [10:0] left_reg, left_next;
    reg [10:0] right_reg, right_next;

    // Ovo je za pravljenje neg_edge za PS2 CLK
    reg ps2_prosli_reg, ps2_prosli_next;
    reg ps2_trenutni_reg, ps2_trenutni_next;

    reg packet_received_reg, packet_received_next;      // Kad se zavrsio dolazak CELOG paketa


    reg flag_reg, flag_next;                            // Stigao paket od 11 bita (vodimo evidenciju zbog verif.)


    // CT dodele
    assign neg_edge = ps2_prosli_reg & ~ps2_trenutni_reg;
    assign display_data = {left_reg, right_reg};

    assign flag = flag_reg;



    always @(posedge clk, negedge rst_n) begin
        if(!rst_n) begin
            state_reg <= initial_state;
            counter_reg <= 4'd10;
            data_reg <= 11'b0000_0000_000;
            left_reg <= 11'b0000_0000_000;
            right_reg <= 11'b0000_0000_000;

            ps2_prosli_reg <= 1'b0;
            ps2_trenutni_reg <= 1'b0;

            packet_received_reg <= 1'b0;

            flag_reg <= 1'b0;
        end
        else begin
            state_reg <= state_next;
            counter_reg <= counter_next;
            data_reg <= data_next;
            left_reg <= left_next;
            right_reg <= right_next;

            ps2_prosli_reg <= ps2_prosli_next;
            ps2_trenutni_reg <= ps2_trenutni_next;

            packet_received_reg <= packet_received_next;

            flag_reg <= flag_next;
        end
    end


    always @(*) begin
        state_next = state_reg;
        counter_next = counter_reg;
        data_next = data_reg;
        left_next = left_reg;
        right_next = right_reg;


        ps2_trenutni_next = ps2_clk;                    // Kao sa vezbi za debouncer
        ps2_prosli_next = ps2_trenutni_reg;

        packet_received_next = packet_received_reg;

        flag_next = flag_reg;



        case (state_reg)

            initial_state:
            begin
                // Resetujemo flag za obradu 11 bita
                flag_next = 1'b0;
                if(neg_edge && !ps2_data) begin             // Ako hoces da testiras da ti dodje 1 na pocetku kao start, onda pisi ovaj if bez && !ps2_data
                    //counter_next = 4'b1010;
                    data_next[10] = ps2_data;
                    state_next = read_state;
                end
            end

            read_state:
            begin
                if(neg_edge) begin
                    data_next = {ps2_data, data_reg[10:1]};
                    counter_next = counter_reg - 4'h1;
                end

                if(counter_reg == 4'h0)
                begin
                    // Stigao ceo paket
                    counter_next = 4'd10;
                    state_next = display_state;
                end
            end

            display_state:
            begin
                if( (data_reg[8:1] != 8'hF0 && data_reg[8:1] != 8'hE0) ) begin
                    
                    if(left_reg[8:1] == 8'h00) begin
                        left_next = 11'b0000_0000_000;
                        right_next = data_reg;
                        state_next = initial_state;
                    end

                    else if(left_reg[8:1] == 8'hF0) begin

                        if(packet_received_reg == 1'b1) begin
                            left_next = 11'b0000_0000_000;
                            right_next = data_reg;
                            state_next = initial_state;
                            packet_received_next = 1'b0;         // Resetujemo zbog primanja novog paketa
                        end
                        else begin
                            left_next = left_reg;       // zadrzavamo stari left reg tj. F0 vrednost
                            right_next = data_reg;
                            state_next = initial_state;
                            packet_received_next = 1'b1;         // Primili smo ceo paket
                        end
                    end

                    else if(left_reg[8:1] == 8'hE0) begin
                        left_next = left_reg;           // zadrzavamo stari left reg tj. E0 vrednost
                        right_next = data_reg;
                        state_next = initial_state;
                    end

                end

                else if( data_reg[8:1] == 8'hF0 ) begin
                    left_next = data_reg;// stavi F0 u levi
                    // desni ne stavljamo jer je ostalo od prethodno pritisnutog desnog
                    state_next = initial_state;
                    packet_received_next = 1'b0;            // Primamo levu stranu pa paket jos uvek nije stigao ceo

                end

                else if( data_reg[8:1] == 8'hE0 ) begin
                    left_next = data_reg;
                    // desni ne stavljamo jer je ostalo od prethodno pritisnutog desnog
                    state_next = initial_state;
                    packet_received_next = 1'b0;            // Primamo levu stranu pa paket jos uvek nije stigao ceo
                end



            // Obradili 11 bita paketa
            flag_next = 1'b1;


            end

            
        endcase

    end

endmodule