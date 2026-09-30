<service>
  <id>SmartAcessoCore</id>
  <name>SmartAcesso Core</name>
  <description>Nucleo SmartAcesso (API local, sincronizacao e dispositivos)</description>
  <executable>%BASE%\jre\bin\java.exe</executable>
  <workingdirectory>%BASE%</workingdirectory>
  <arguments>-Xms256m -Xmx1024m -Dfile.encoding=UTF-8 -Dsmartacesso.data.dir=@@PROGRAMDATA@@\data\core\database -jar "%BASE%\smartacesso.jar" --spring.config.additional-location=file:///@@PROGRAMDATA_URI@@/config/core/</arguments>
  <logpath>@@PROGRAMDATA@@\logs\core</logpath>
  <log mode="roll-by-size">
    <sizeThreshold>10240</sizeThreshold>
    <keepFiles>8</keepFiles>
  </log>
  <onfailure action="restart" delay="10 sec"/>
  <stoptimeout>20 sec</stoptimeout>
  <startmode>Automatic</startmode>
</service>
