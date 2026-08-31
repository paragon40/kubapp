
class PythonHandler:
    def __init__(self, manifest, dockerfile=False):
      self.manifest = manifest
      self.dockerfile = dockerfile
      self.app_dir  = manifest.parent

    def install_dependencies(self):
        pass

    def lint(self):
        pass

    def security_analysis(self):
        pass

    def unit_tests(self):
        pass

    def build(self):
        pass

    def docker_build(self):
        if not self.dockerfile:
          print("")
          return
        
