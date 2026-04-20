/* Quartus II 32-bit Version 13.0.1 — JTAG SRAM configuration (volatile) */
JedecChain;
	FileRevision(JESD32A);
	DefaultMfr(6E);

	P ActionCode(Ign)
		Device PartName(EP2C5) MfrSpec(OpMask(0) FullPath("/home/dmj/code/fpga/ep5c8-counter/quartus/flash.jam"));
	P ActionCode(Cfg)
		Device PartName(EP2C5T144) Path("/home/dmj/code/fpga/dkcpu/quartus/") File("dkcpu.sof") MfrSpec(OpMask(1) SEC_Device(EPCS4) Child_OpMask(1 0));

ChainEnd;

AlteraBegin;
	ChainType(JTAG);
AlteraEnd;
