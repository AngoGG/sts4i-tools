<?xml version="1.0" encoding="UTF-8"?>
<p:declare-step xmlns:p="http://www.w3.org/ns/xproc"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  xmlns:c="http://www.w3.org/ns/xproc-step"
  xmlns:cx="http://xmlcalabash.com/ns/extensions" 
  xmlns:tr="http://transpect.io"
  xmlns:sc="http://transpect.io/schematron-config"
  xmlns:sch="http://purl.oclc.org/dsdl/schematron" 
  xmlns:svrl="http://purl.oclc.org/dsdl/svrl"
  version="1.0" 
  name="apply-fixes" type="tr:apply-xsl-fixes">

  <p:input port="reports" primary="true">
    <p:documentation>A reports wrapper document as generated by tr:batch-val-sts. The xml:base attributes 
    contain the base URIs of the validated files, plus an extension '.val'. The IDs of svrl:failed-assert
    or svrl:successful-report messages will be used to look up sc:fix-xsl attributes in the assembled Schematron
    file in order to identify URIs of fixing XSLT (resolved against their sch:pattern’s base URI).</p:documentation>
  </p:input>
  <p:input port="source" sequence="true">
    <p:documentation>The validated STS source documents. They will be selected by base URI (as calculated from the
      SVRL’s base URI, minus trailing '.val'). If there is no such document on this port, an attempt is made to load it
      from the location given by the report’s base URI.</p:documentation>
    <p:empty/>
  </p:input>
  <p:input port="schematron">
    <p:documentation>An assembled Schematron document, possibly with sc:fix-xsl attributes.</p:documentation>
  </p:input>
  <p:input port="params" kind="parameter"/>

  <p:output port="result" primary="true" sequence="true">
    <p:documentation>The hopefully fixed documents from the source port. The base URI will be augmented by replacing
    an '.xml' suffix by '.fixed.xml'.</p:documentation>
  </p:output>

  <p:option name="debug-dir-uri" select="''"/>
  <p:option name="debug" select="'no'"/>

  <p:import href="http://transpect.io/xproc-util/file-uri/xpl/file-uri.xpl"/>
  <p:import href="http://xmlcalabash.com/extension/steps/library-1.0.xpl"/>
  <p:import href="http://transpect.io/xproc-util/load/xpl/load-sources.xpl"/>
  <p:import href="http://transpect.io/xproc-util/store-debug/xpl/store-debug.xpl"/>

  <p:declare-step type="tr:apply-fixes-recursion" name="apply-fixes-recursion-decl">
    <p:input port="fixes" primary="true">
      <p:documentation>A sc:fixes-list document with sc:xsl-fix children. The first sc:xsl-fix will be applied,
      then this sc:xsl-fix element will be removed and the step will be invoked with the remaining sch:schema
      document, until all sc:xsl-fixes have been removed from the document.
      The purpose of this recursion is that each subsequent fix be applied to the output of the preceding fix.
      This is not possible with a plain p:for-each iteration over all sc:xsl-fixes.</p:documentation>
    </p:input>
    <p:input port="source">
      <p:documentation>The document to be fixed</p:documentation>
    </p:input>
    <p:input port="params" kind="parameter"/>
    <p:output port="result" primary="true"/>
    
    <p:option name="debug-dir-uri" select="''"/>
    <p:option name="debug" select="'no'"/>
    
    <p:import href="http://transpect.io/xproc-util/store-debug/xpl/store-debug.xpl"/>

    <p:parameters name="consolidate-params">
      <p:input port="parameters">
        <p:pipe port="params" step="apply-fixes-recursion-decl"/>
      </p:input>
    </p:parameters> 

    <p:identity name="get-primary-sources-back-on-the-DRP">
      <p:input port="source">
        <p:pipe port="fixes" step="apply-fixes-recursion-decl"/>
      </p:input>
    </p:identity>
    
    <p:for-each name="fix-source">
      <p:iteration-source select="/sc:fixes-list/sc:xsl-fix[1]"/>
      <p:output port="result" primary="true"/>
      <p:variable name="iteration-position" select="/*/@pos"/>
      <p:variable name="fix-xsl-href" select="/sc:xsl-fix/@href"/>
      <p:variable name="fix-xsl-mode" select="xs:QName(/sc:xsl-fix/@mode)" cx:type="xs:QName"/>
      <p:load name="load-xsl">
        <p:with-option name="href" select="$fix-xsl-href"/>
      </p:load>
      <p:sink name="sink4"/>
      <p:xslt name="fix-current-source-doc">
        <p:with-option name="output-base-uri" select="replace(base-uri(/*), '(\.fixed)?\.xml$', '.fixed.xml')">
          <p:pipe port="source" step="apply-fixes-recursion-decl"/>
        </p:with-option>
        <p:with-option name="initial-mode" select="$fix-xsl-mode"/>
        <p:input port="source">
          <p:pipe port="source" step="apply-fixes-recursion-decl"/>
        </p:input>
        <p:input port="parameters" select="/sc:xsl-fix/c:param-set">
          <p:pipe port="current" step="fix-source"/>
        </p:input>
        <p:input port="stylesheet">
          <p:pipe port="result" step="load-xsl"/>
        </p:input>
      </p:xslt>
      <p:add-attribute name="make-fixed-xml-base-explicit" attribute-name="xml:base" match="/*">
        <p:documentation>output-base-uri apparently doesn't change as requested</p:documentation>
        <p:with-option name="attribute-value" select="replace(base-uri(/*), '(\.fixed)?\.xml$', '.fixed.xml')"/>
      </p:add-attribute>
      <cx:message>
        <p:with-option name="message" select="'VVVVVVVVVVV ', ' ;; &#xa;', base-uri(/*), ' :: ', replace(base-uri(/*), '(\.fixed)?\.xml$', '.fixed.xml')"/>
      </cx:message>
      <tr:store-debug name="store-patched">
        <p:with-option name="active" select="$debug"/>
        <p:with-option name="base-uri" select="$debug-dir-uri"/>
        <p:with-option name="pipeline-step" 
          select="string-join(('apply-fix', $iteration-position,
                               replace(base-uri(/*), '^.+/(.+?)\.xml$', '$1'), 
                               replace($fix-xsl-href, '^.+/(.+?)\.xsl$', '$1'),
                               replace($fix-xsl-mode, ':', '_')),
                              '__')"/>
      </tr:store-debug>
    </p:for-each>
    <p:count name="count-fixed-doc"/>
    <p:choose name="conditionally-recurse">
      <p:when test=". = 0">
        <p:output port="result" primary="true"/>
        <p:documentation>no more fixes, return souce</p:documentation>
        <p:identity>
          <p:input port="source">
            <p:pipe port="source" step="apply-fixes-recursion-decl"/>
          </p:input>
        </p:identity>
      </p:when>
      <p:otherwise>
        <p:output port="result" primary="true"/>
        <p:delete match="/sc:fixes-list/sc:xsl-fix[1]">
          <p:input port="source">
            <p:pipe port="fixes" step="apply-fixes-recursion-decl"/>
          </p:input>
        </p:delete>
        <tr:apply-fixes-recursion name="encore">
          <p:input port="source">
            <p:pipe port="result" step="fix-source"/>
          </p:input>
          <p:input port="params">
            <p:pipe port="result" step="consolidate-params"/>
          </p:input>
          <p:with-option name="debug" select="$debug"/>
          <p:with-option name="debug-dir-uri" select="$debug-dir-uri"/>
        </tr:apply-fixes-recursion>
      </p:otherwise>
    </p:choose>
  </p:declare-step>

  <p:variable name="error-ids-with-fixes" select="string-join(//(sch:assert | sch:report)[sc:xsl-fix]/@id, ' ')">
    <p:pipe port="schematron" step="apply-fixes"/>
  </p:variable>
  <p:variable name="report-uris-with-fixes"
     select="string-join(
               distinct-values(//(svrl:failed-assert | svrl:successful-report)
                                   [@id = tokenize($error-ids-with-fixes, '\s+')]/ancestor::*[@xml:base][1]/@xml:base),
               ' ')"/>
  <p:variable name="source-uris-with-fixes"
     select="string-join(
               for $ru in tokenize($report-uris-with-fixes, '\s+') return replace($ru, '\.val$', ''),
               ' ')"/>
  <!--<cx:message>
    <p:with-option name="message" select="'§§§§§§§§§§§§§§§§§§§§ 1111111 ', $error-ids-with-fixes, ' :: ', $report-uris-with-fixes"></p:with-option>
  </cx:message>
  <p:sink></p:sink>-->
  <p:parameters name="consolidate-params">
    <p:input port="parameters">
      <p:pipe port="params" step="apply-fixes"/>
    </p:input>
  </p:parameters>
  <tr:load-sources name="load-sources" add-xml-base="true">
    <p:input port="source">
      <p:pipe port="source" step="apply-fixes"/>
    </p:input>
    <p:with-option name="uris" select="$source-uris-with-fixes"/>
  </tr:load-sources>
  <tr:store-debug name="store-loaded-sources">
    <p:with-option name="active" select="$debug"/>
    <p:with-option name="base-uri" select="$debug-dir-uri"/>
    <p:with-option name="pipeline-step" select="'load-sources'"/>
  </tr:store-debug>
  <p:for-each name="source-iteration">
    <p:variable name="base-uri" select="base-uri(/*)"/>
    <p:variable name="this-documents-error-ids-with-fixes" 
      select="string-join(
                distinct-values(/reports/svrl:schematron-output[@xml:base = concat($base-uri, '.val')]
                        /(svrl:failed-assert | svrl:successful-report)/@id[. = tokenize($error-ids-with-fixes, '\s+')]),
                ' ')">
      <p:pipe port="reports" step="apply-fixes"/>
    </p:variable>
    <p:add-attribute match="/*" attribute-name="xml:base">
      <p:with-option name="attribute-value" select="$base-uri"/>
    </p:add-attribute>
    <tr:store-debug name="store-fix-source">
      <p:with-option name="active" select="$debug"/>
      <p:with-option name="base-uri" select="$debug-dir-uri"/>
      <p:with-option name="pipeline-step" select="'fixes-source'"/>
    </tr:store-debug>
    <cx:message>
      <p:with-option name="message" select="'3333333 ', $base-uri, ' :: ', $this-documents-error-ids-with-fixes"/> 
    </cx:message>
    <p:xslt name="select-fixes-for-current-doc" template-name="main">
      <p:with-param name="ids" select="$this-documents-error-ids-with-fixes"/>
      <p:with-param name="base-uri" select="$base-uri"/>
      <p:input port="parameters"><p:empty/></p:input>
      <p:input port="source">
        <p:pipe port="schematron" step="apply-fixes"/>
        <p:pipe port="reports" step="apply-fixes"/>
      </p:input>
      <p:input port="stylesheet">
        <p:inline>
          <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="2.0">
            <xsl:param name="ids" as="xs:string"/>
            <xsl:param name="base-uri" as="xs:string"/>
            <xsl:key name="by-id" match="*[@id]" use="@id"/>
            <xsl:key name="by-test-id" match="*[@test-id]" use="@test-id"/>
            <xsl:template name="main">
              <xsl:variable name="svrl-doc" as="document-node(element(svrl:schematron-output))">
                <xsl:document>
                  <xsl:sequence select="collection()/reports/svrl:schematron-output[@xml:base = concat($base-uri, '.val')]"/>
                </xsl:document>
              </xsl:variable>
              <xsl:apply-templates select="$svrl-doc/svrl:schematron-output">
                <xsl:with-param name="schematron" as="document-node(element(sch:schema))" select="collection()[sch:schema]" tunnel="yes"/>
              </xsl:apply-templates>
            </xsl:template>
            <xsl:template match="/svrl:schematron-output">
              <xsl:param name="schematron" tunnel="yes" as="document-node(element(sch:schema))"/>
              <xsl:variable name="svrl" as="document-node()" select=".."/>
              <xsl:message select="'aaaaaaaa ', $ids, count(tokenize($ids, '\s+')), count(key('by-id', tokenize($ids, '\s+')))"></xsl:message>
              <sc:fixes-list>
                <xsl:attribute name="xml:base" select="$base-uri"/>
                <xsl:for-each-group select="tokenize($ids, '\s+') ! key('by-test-id', ., $svrl)[1] ! sc:prepend-prerequisites(., $svrl, $schematron)" 
                  group-by="string-join((@href, @mode, sc:param/@*), '__')">
                  <xsl:apply-templates select="."/>
                </xsl:for-each-group>
              </sc:fixes-list>
            </xsl:template>
            <xsl:function name="sc:prepend-prerequisites" as="element(sc:xsl-fix)+">
              <xsl:param name="fix" as="element(sc:xsl-fix)+"/>
              <xsl:param name="svrl" as="document-node(element(svrl:schematron-output))"/>
              <xsl:param name="schematron" as="document-node(element(sch:schema))"/>
              <xsl:for-each select="$fix/@depends-on (: id of an sch:assert or sch:report with an sc:xsl-fix :)">
                <xsl:variable name="dependencies-found-in-svrl" as="element(sc:xsl-fix)*"
                    select="tokenize(., '\s+') ! key('by-test-id', ., $svrl)[1]"/>
                <xsl:variable name="fallback-dependencies-found-in-schematron" as="element(sc:xsl-fix)*"
                    select="tokenize(., '\s+')[not(. = $dependencies-found-in-svrl/@test-id)] ! key('by-test-id', ., $schematron)[1]"/>
                <xsl:sequence select="sc:prepend-prerequisites(($dependencies-found-in-svrl, $fallback-dependencies-found-in-schematron), $svrl, $schematron)"/>
              </xsl:for-each>
              <xsl:apply-templates select="$fix">
                <xsl:with-param name="schematron" select="$schematron" as="document-node(element(sch:schema))" tunnel="yes"/>
              </xsl:apply-templates>
            </xsl:function>
            <xsl:template match="sc:xsl-fix">
              <xsl:param name="schematron" as="document-node(element(sch:schema))" tunnel="yes"/>
              <xsl:if test="local-name(..) = ('report', 'assert') and empty(../@id)">
                <xsl:message terminate="yes" select="'This schematron element neeeds an ID: ', .."/>
              </xsl:if>
              <xsl:variable name="fix-in-schematron" select="key('by-test-id', @test-id, $schematron)[1]"/>
              <xsl:copy>
                <xsl:attribute name="href" select="resolve-uri(@href, base-uri($fix-in-schematron))"/>
                <xsl:copy-of select="@* except @href, node()"/>
                <!-- apply-templates of sc:param does not work, probably due to a Calabash bug.
                  This and other strange things only happen when sc:xsl-fix occur both in Schematron and XVRL documents. -->  
              </xsl:copy>
            </xsl:template>
            <xsl:template match="sc:param"><!-- won’t match, bug -->
            </xsl:template>
          </xsl:stylesheet>
        </p:inline>
      </p:input>
    </p:xslt>

    <p:xslt name="param-sets">
      <p:input port="parameters"><p:empty/></p:input>
      <p:input port="stylesheet">
        <p:inline>
          <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="2.0">
            <xsl:template match="node() | @*">
              <xsl:copy>
                <xsl:apply-templates select="node() | @*"/>
              </xsl:copy>
            </xsl:template>
            <xsl:template match="@test-id">
              <xsl:next-match/>
              <xsl:attribute name="pos" select="index-of(../../sc:xsl-fix/generate-id(), ../generate-id())"></xsl:attribute>
            </xsl:template>
            <xsl:template match="*:xsl-fix[*:param]">
              <xsl:copy>
                <xsl:apply-templates select="@*"/>
                <c:param-set>
                  <xsl:apply-templates/>
                </c:param-set>
              </xsl:copy>
            </xsl:template>
            <xsl:template match="sc:param">
              <!-- this is the reason why we use the sc:xsl-fix from SVRL rather than from Schematron (that we use as fallback
                if there is no failed-assert/successful-report for a given dependency in the SVRL) --> 
              <xsl:message select="'PPPPPPPPPPPPPPAAAAAAAAAAAAAAAAAa ', string(@name), ' :: ', string(.), ' :: ', ."></xsl:message>
              <c:param name="{@name}" value="{string(.)}"/>
            </xsl:template>
          </xsl:stylesheet>
        </p:inline>
      </p:input>
    </p:xslt>

    <cx:message>
      <p:with-option name="message" select="'444444444 ', count(/*/*), /*/*/name()"></p:with-option>
    </cx:message>
    <tr:store-debug name="store-fix-list">
        <p:with-option name="active" select="$debug"/>
        <p:with-option name="base-uri" select="$debug-dir-uri"/>
        <p:with-option name="pipeline-step" 
          select="'fixes-list'"/>
      </tr:store-debug>
    <tr:apply-fixes-recursion name="apply-fixes-recursion">
      <p:input port="source">
        <p:pipe port="current" step="source-iteration"/>
      </p:input>
      <p:input port="params">
        <p:pipe port="result" step="consolidate-params"/>
      </p:input>
      <p:with-option name="debug" select="$debug"/>
      <p:with-option name="debug-dir-uri" select="$debug-dir-uri"/>
    </tr:apply-fixes-recursion>
  </p:for-each>
</p:declare-step>
