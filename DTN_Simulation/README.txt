1. Go to Command Window.
2. type "cfg = struct();" then enter.
3. type "cfg.orbitClass = "LEO";" for LEO orbit | "cfg.orbitClass = "MEO";" for MEO orbit | "cfg.orbitClass = "GEO";" for GEO orbit -> then enter.
4. type "S = dtn_two_gs(cfg);" -> then enter to get results.
5. type "dtn_summary_window(S);" -> then enter to summarize results.
6. type "sc = dtn_globe_viewer(S);" -> then enter to create visuals. 
