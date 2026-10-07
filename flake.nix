{
  description = "Plugins for uji";

  outputs =
    { self }:
    {
      # Typed options for these plugins in uji's home-manager module; importing
      # it also loads this pack
      homeModules.default = import ./nix/module.nix self;
      homeManagerModules = self.homeModules;
    };
}
