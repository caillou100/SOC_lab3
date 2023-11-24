module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
    output  wire                     awready,//lite write
    output  wire                     wready, //看懂訊號
    input   wire                     awvalid, //coefficient input(AXI-lite) 
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid, //coefficient input(AXI-lite)
    input   wire [(pDATA_WIDTH-1):0] wdata,  //coef data

    output  wire                     arready,//傳回tb對答案
    input   wire                     rready,
    input   wire                     arvalid, //Check Coefficient
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,    //read

    input   wire                     ss_tvalid, //stream write?
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  wire                     ss_tready,

    input   wire                     sm_tready, //stream read
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM coe存進tap
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,//data in
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,//data out

    // bram for data RAM 存axi data
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);

//coefcontrol in
    reg [11:0]  count_w,count_r;
    reg [4:0]   state_w,state_r;
    reg [31:0]  coefdata_w,coefdata_r,coefaddr_w,coefaddr_r;
    reg [3:0]   coefcount_w,coefcount_r;
    reg         awready_w,awready_r,wready_w,wready_r;
    assign tap_EN = 1;
    assign tap_WE = (state_r==1 ||state_r==2)?4'b1111:4'b0;
    assign tap_Di = coefdata_r;
    assign tap_A  = coefaddr_r - (6'b100000);
    assign wready = wready_r;
//coefcontrol out
    reg rvalid_w,rvalid_r;

    assign rdata = coefdata_r;
    assign rvalid = rvalid_r;

//input data
    reg ss_tready_w,ss_tready_r;
    reg [11:0] inaddr_w,inaddr_r;
    wire [31:0] indata;

//pipeline
//out data
    reg signed [31:0] acc_w,acc_r;
    reg        [11:0] odataaddr_w,odataaddr_r;
    reg         [3:0]  account_w,account_r;

    assign ss_tready = ss_tready_r;
    assign data_Di = (state_r==8)?0:ss_tdata;
    assign data_EN = 1;
    assign data_A = odataaddr_r;
    assign data_WE = (ss_tready_r || state_r==8)?4'b1111:0;
    assign sm_tvalid = (state_r == 7)?1:0;
    assign sm_tdata = acc_r;



    parameter   Idle = 0,
                Coef_load = 1,
                Coef_save = 2,
                Coef_check_idel = 3,
                Coef_check = 4,
                Load_ele = 5,
                ALU = 6,
                Out_y = 7,
                Reram =8;

// write your code here!
//獨到apstart 開始讀到axi
// 11coe 11axi
    always@(*)begin
        count_w = count_r;
        state_w = state_r;
        coefdata_w = coefdata_r;
        coefcount_w = coefcount_r;
        coefaddr_w = coefaddr_r;
        awready_w = awready_r;
        wready_w = wready_r;
        rvalid_w = rvalid_r;
        ss_tready_w = ss_tready_r;
        inaddr_w = inaddr_r;
        odataaddr_w = odataaddr_r;
        acc_w = acc_r;
        account_w = account_r;

        case (state_r)
            Idle:begin
                if (axis_rst_n) begin
                    state_w = 8;
                end
            end
            
            Reram:begin
                count_w = count_r+1;
                odataaddr_w = odataaddr_r + 4;
                if (count_r == 11) begin
                    odataaddr_w = 0;
                    count_w = 0;
                    state_w = 1;
                end
            end

            Coef_load:begin
                if (awvalid && wvalid) begin
                    awready_w = 1;
                    wready_w = 1;
                    coefaddr_w = awaddr;
                    coefdata_w = wdata;
                    coefcount_w = coefcount_r + 1;
                    state_w = 2;
                end
            end

            Coef_save:begin
                state_w = (coefcount_r == 12)?3:1;
            end

            Coef_check_idel: begin
                coefaddr_w = 6'b100000;         
                coefcount_w = 0;
                coefdata_w = tap_Do;
                state_w = 4;
            end

            Coef_check:begin
                if(arvalid ==1 && rready==1)begin
                    coefaddr_w = (coefcount_r>=10)?6'b100000:coefaddr_r + 4;
                    coefcount_w = coefcount_r + 1;
                    rvalid_w = 1;
                    state_w = (coefcount_r==11)?5:state_r;
                    //前置作業
                    ss_tready_w = (coefcount_r==11)?1:0;
                end
                coefdata_w = tap_Do;
            end

            Load_ele:begin
                inaddr_w =(inaddr_r==40)?0:inaddr_r+4;
                ss_tready_w = 0;
                state_w = 6;
                count_w = 0;
                //ALU預備
                odataaddr_w = (odataaddr_r==0)?40:inaddr_r-4;
                coefaddr_w = 6'b100000+4;
                acc_r = 0;
            end

            ALU:begin
                odataaddr_w = (odataaddr_r==0)?40:odataaddr_r-4;
                coefaddr_w = (tap_A==40)?6'b100000:coefaddr_r+4;
                acc_w = (account_r==0)?0:($signed(data_Do) * $signed(tap_Do) + $signed(acc_r));
                account_w = account_r+1;
                state_w = (account_r==10)?7:state_r;
            end

            Out_y:begin
                odataaddr_w = inaddr_r;
                account_w = 0;
                ss_tready_w = 1;
                state_w = 5;
                if (sm_tlast==1) begin
                    state_w = 8;
                end
            end

            default: state_w = 9;
        endcase
    end




    always @(posedge axis_clk or posedge axis_rst_n) begin
        if(~axis_rst_n)begin
            count_r <= 0;
            state_r <= 0;
            coefdata_r <= 0;
            wready_r <= 0;
            coefcount_r <= 0;
            coefaddr_r <= 0;
            awready_r <= 0;
            wready_r <= 0;
            rvalid_r <= 0;
            ss_tready_r <= 0;
            inaddr_r <= 0;
            odataaddr_r <= 0;
            acc_r <= 0;
            account_r <= 0;
        end else begin
            count_r <= count_w;
            state_r <= state_w;
            coefdata_r <= coefdata_w;
            wready_r <= wready_w;
            coefcount_r <= coefcount_w;
            coefaddr_r <= coefaddr_w;
            awready_r <= awready_w;
            wready_r <= wready_w;
            rvalid_r <= rvalid_w;
            ss_tready_r <= ss_tready_w;
            inaddr_r <= inaddr_w;
            odataaddr_r <= odataaddr_w;
            acc_r <= acc_w;
            account_r <= account_w;
        end

    end 
//end
endmodule