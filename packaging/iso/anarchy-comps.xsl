<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">

    <!--
        This XSLT extracts selected groups and environments from the upstream
        distribution comps file. It now selects the updated AnarchyHPC group
        and environment instead of the legacy TrinityX definitions.
    -->

    <xsl:template match="/" name="identity">

        <!-- Standard OS groups -->
        <xsl:copy-of select="comps/group/id[text()='core']/.."/>
        <xsl:copy-of select="comps/group/id[text()='base']/.."/>
        <xsl:copy-of select="comps/group/id[text()='debugging']/.."/>
        <xsl:copy-of select="comps/group/id[text()='development']/.."/>
        <xsl:copy-of select="comps/group/id[text()='hardware-monitoring']/.."/>
        <xsl:copy-of select="comps/group/id[text()='network-tools']/.."/>
        <xsl:copy-of select="comps/group/id[text()='performance']/.."/>
        <xsl:copy-of select="comps/group/id[text()='system-admin-tools']/.."/>
        <xsl:copy-of select="comps/group/id[text()='system-management']/.."/>

        <!-- Standard minimal environment -->
        <xsl:copy-of select="comps/environment/id[text()='minimal']/.."/>

        <!-- Updated AnarchyHPC group -->
        <xsl:copy-of select="comps/group/id[text()='anarchyhpc']/.."/>

        <!-- Updated AnarchyHPC environment -->
        <xsl:copy-of select="comps/environment/id[text()='anarchyhpc']/.."/>

    </xsl:template>

    <xsl:template match="/">
        <xsl:call-template name="identity" />
    </xsl:template>

</xsl:stylesheet>
