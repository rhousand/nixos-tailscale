{
  pkgs,
  config,
  gladstoneArgs,
  ...
}: {
  age = {
    age.identityPaths = [ 
        "/root/.config/age/"
        "/root/.ssh/"
        ];
    secrets = {
      tsKeyAge = {
        file = gladstoneArgs.tsKeyAgeFile;
        owner = "root";
        group = "root";
        permissions = "0400";
      };
    };
  };
}