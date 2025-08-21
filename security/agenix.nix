{
  pkgs,
  config,
  gladstoneArgs,
  ...
}: {
  age = {
    secrets = {
      tsKeyAge.file = gladstoneArgs.tsKeyAgeFile;
    };
  };
}