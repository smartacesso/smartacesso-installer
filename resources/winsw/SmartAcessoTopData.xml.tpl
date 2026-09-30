<service>
  <id>SmartAcessoTopData</id>
  <name>SmartAcesso TopData</name>
  <description>Integracao SmartAcesso com equipamentos TopData</description>
  <executable>%BASE%\jre\bin\java.exe</executable>
  <workingdirectory>%BASE%</workingdirectory>
  <arguments>-Xms256m -Xmx1024m -Dfile.encoding=UTF-8 -Djava.library.path="%BASE%\native" -Dsmartacesso.data.dir=@@PROGRAMDATA@@\data\topdata\database -jar "%BASE%\topdata.jar" --spring.config.additional-location=file:///@@PROGRAMDATA_URI@@/config/topdata/</arguments>
  <env name="PATH" value="%BASE%\native;%PATH%"/>
  <logpath>@@PROGRAMDATA@@\logs\topdata</logpath>
  <log mode="roll-by-size">
    <sizeThreshold>10240</sizeThreshold>
    <keepFiles>8</keepFiles>
  </log>
  <onfailure action="restart" delay="10 sec"/>
  <stoptimeout>20 sec</stoptimeout>
  <startmode>Automatic</startmode>
</service>
